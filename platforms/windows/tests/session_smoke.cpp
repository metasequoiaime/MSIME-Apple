#include "KeyEvent.h"
#include "ReplyCodec.h"
#include "ServerSession.h"
#include "ipc_negotiation.h"
#include <chrono>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#ifdef _WIN32
#include <windows.h>
static_assert(VK_BACK == 0x08 && VK_RETURN == 0x0D && VK_SPACE == 0x20);
static_assert(VK_PRIOR == 0x21 && VK_NEXT == 0x22 && VK_DELETE == 0x2E);
static_assert(VK_NUMPAD0 == 0x60 && VK_NUMPAD9 == 0x69 && VK_LSHIFT == 0xA0);
#endif

using Json = nlohmann::json;
using msime::windows::ServerSession;
namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
template <class F> void rejected(F action) {
  bool failed = false;
  try {
    action();
  } catch (const std::exception &) {
    failed = true;
  }
  require(failed, "Invalid request was accepted");
}
} // namespace
int main(int argc, char **argv) {
  try {
    auto root =
        std::filesystem::temp_directory_path() /
        ("msime-windows-session-" +
         std::to_string(
             std::chrono::steady_clock::now().time_since_epoch().count()));
    require(std::filesystem::create_directory(root),
            "Cannot create isolated test root");
    struct Cleanup {
      std::filesystem::path path;
      ~Cleanup() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
      }
    } cleanup{root};
    Json preferences = {{"scheme", "quanpin"},
                        {"learning", false},
                        {"chinese_punctuation", true},
                        {"candidate_page_size", 2}};
    auto directory = [&](const char *name) {
      auto path = root / name;
      std::filesystem::create_directory(path);
      return path.u8string();
    };
    Json options = {{"api_version", 1},
                    {"resources", directory("resources")},
                    {"user_data", directory("user")},
                    {"cache", directory("cache")},
                    {"dictionaries", directory("dictionaries")},
                    {"preferences", preferences}};
    if (argc == 2) {
      auto input = Json{{"resources", argv[1]},
                        {"state_root", (root / "prepared").u8string()}}
                       .dump();
      std::unique_ptr<char, decltype(&msime_client_string_free)> prepared(
          msime_client_prepare_host(
              reinterpret_cast<const uint8_t *>(input.data()), input.size()),
          msime_client_string_free);
      auto document = Json::parse(prepared.get());
      require(document.at("ok").get<bool>(),
              "Locked dictionary preparation failed");
      options = document.at("value");
      options["preferences"] = preferences;
    }
    // Protocol definitions and x86/x64 layout assertions are imported, not
    // copied.
    auto hello =
        FanyImeProtocol::Hello(42, 1, FanyImeProtocol::RequiredCapabilities);
    require(
        FanyImeProtocol::Negotiate(hello, FanyImeProtocol::RequiredCapabilities)
            .accepted,
        "Shared protocol negotiation failed");
    ServerSession session(42, options.dump());
    uint64_t request = 2;
    uint64_t epoch = 1;
    auto key = [&](uint32_t vk, uint32_t text = 0, uint32_t modifiers = 0) {
      FanyImeNamedpipeData packet{};
      packet.event_type = FanyImePipeEventType::KeyEvent;
      packet.client_id = 42;
      packet.request_id = request++;
      packet.keycode = vk;
      packet.wch = static_cast<FanyImeWireChar>(text);
      packet.modifiers_down = modifiers;
      // TSF's preview text cannot overwrite the Engine's composition owner.
      packet.pinyin_length = 3;
      packet.pinyin_string[0] = 'x';
      auto result = session.key(packet, epoch);
      require(result.request_id == packet.request_id &&
                  result.client_id == 42 && result.activation_epoch == epoch,
              "Reply routing metadata lost");
      return result;
    };
    rejected([&] { key('U', 'U', 1); });
    session.activate(epoch);
    key('U', 'U', 1 | FanyImePipeFlags::UiLess);
    for (char c : std::string("4e2d"))
      key(static_cast<uint32_t>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c), c);
    auto before = session.view();
    require(before.at("editing_text") == "U4e2d",
            "TSF text overwrote shared composition");
    auto stale_generation = before.at("generation").get<uint64_t>();
    preferences["chinese_punctuation"] = false;
    auto snapshot = Json{
        {"format_version", 1},
        {"revision", 1},
        {"preferences",
         preferences}}.dump();
    require(session.update_preferences(epoch, snapshot).at("deferred") == true,
            "Active preferences not deferred");
    auto selected = key(0x20);
    require(selected.transition.at("commit") == "中" && selected.reply_expected,
            "Unicode commit failed");
    auto reply = msime::windows::candidate_commit(
        selected.request_id,
        selected.transition.at("commit").get<std::string>());
    require(reply && reply.packet.request_id == selected.request_id &&
                reply.packet.candidate_string[0] == 0x4E2D,
            "Shared result did not encode into the candidate reply");
    rejected([&] { session.select(epoch, stale_generation, 0); });
    require(key(0xBC, ',').transition.at("handled") == false,
            "Deferred ASCII punctuation not applied");
    key('U', 'U', 1);
    auto shortcut = key('C', 0, 2);
    require(shortcut.transition.at("handled") == false &&
                session.view().at("editing_text") == "",
            "Shortcut did not cancel and forward");
    key('U', 'U', 1);
    FanyImeNamedpipeData reset{};
    reset.event_type = FanyImePipeEventType::KeyEvent;
    reset.client_id = 42;
    reset.keycode = 0x10;
    require(!session.key(reset, epoch).reply_expected &&
                session.view().at("editing_text") == "",
            "Local TSF reset emitted reply or kept composition");
    reset.keycode = 'A';
    rejected([&] { session.key(reset, epoch); });
    reset.request_id = 99;
    reset.client_id = 43;
    rejected([&] { session.key(reset, epoch); });
    bool wrong_thread = false;
    std::thread worker([&] {
      try {
        session.view();
      } catch (const std::logic_error &) {
        wrong_thread = true;
      }
    });
    worker.join();
    require(wrong_thread, "Wrong thread accessed the shared session");
    key('U', 'U', 1);
    session.deactivate(epoch);
    require(session.view().at("editing_text") == "",
            "Focus loss retained composition");
    rejected([&] { session.activate(epoch); });
    rejected([&] { key('U', 'U', 1); });
    session.activate(++epoch);
    rejected([&] { session.deactivate(epoch - 1); });
    if (argc == 2) {
      for (char c : std::string("nihao"))
        key(c - 'a' + 'A', c);
      require(session.view().at("candidates").at(0).at("text") == "你好",
              "Published dictionary query failed");
      key(0x22);
      auto page = session.view();
      require(page.at("page") == 1, "Shared page did not advance");
      auto expected = page.at("candidates").at(0).at("text");
      require(key(0x61).transition.at("commit") == expected,
              "Numpad did not select shared page global index");
    }
    std::cout << "Windows Server boundary: shared session, routing and input "
                 "acceptance passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

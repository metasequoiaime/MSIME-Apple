#include "FocusedSession.h"
#include "FocusRouter.h"
#include "InputQueue.h"
#include "KeyEvent.h"
#include "ReplyCodec.h"
#include "ReplyComposer.h"
#include "ServerSession.h"
#include "ipc_negotiation.h"
#include <chrono>
#include <filesystem>
#include <future>
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
void session_pump_tests(const std::string &options);
void session_worker_tests(const std::string &options);
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
    {
      using namespace msime::windows;
      FocusGate gate;
      FocusedSession focused(gate, 42, options.dump());
      PipeTicket ticket{42, {1, 2, 3}};
      auto first = *gate.begin(ticket, 77);
      FanyImeNamedpipeData packet{};
      packet.event_type = FanyImePipeEventType::KeyEvent;
      packet.client_id = 42;
      packet.request_id = 2;
      packet.keycode = 'U';
      packet.wch = 'U';
      packet.modifiers_down = 1;
      require(!focused.key(first.pending, packet, ReplyPath::Composition),
              "Unprepared focus entered Engine");
      require(focused.prepare(first.pending), "Focus preparation failed");
      require(!focused.key(first.pending, packet, ReplyPath::Composition),
              "Unacknowledged focus entered Engine");
      require(focused.view().at("editing_text") == "",
              "Pending focus changed composition");
      require(gate.acknowledge(first.pending, [] { return true; }),
              "Synthetic queue-test fence failed");
      auto initial = focused.key(first.pending, packet, ReplyPath::Composition);
      require(initial && focused.view().at("editing_text") == "U",
              "Focused key did not reach Engine");
      const auto pending_view = focused.view();
      auto updated_preferences = preferences;
      updated_preferences["candidate_page_size"] = 3;
      const auto focused_snapshot = Json{
          {"format_version", 1},
          {"revision", 1},
          {"preferences",
           updated_preferences}}.dump();
      require(!focused.update_preferences(first.pending, focused_snapshot) &&
                  focused.view() == pending_view,
              "Configuration bypassed pending delivery gate");
      ++packet.request_id;
      rejected(
          [&] { focused.key(first.pending, packet, ReplyPath::Composition); });
      require(focused.view() == pending_view,
              "Pending reply allowed another Engine action");
      require(focused.pending(first.pending)->source.request_id ==
                  initial->source.request_id,
              "Staged reply could not be recovered without Engine replay");
      require(focused.confirm(first.pending, initial->source.request_id),
              "Delivery confirmation failed");
      require(!focused.pending(first.pending),
              "Confirmed reply remained staged");
      const auto deferred =
          focused.update_preferences(first.pending, focused_snapshot);
      require(
          deferred && deferred->at("deferred") == true,
          "Focused configuration did not reuse shared composition deferral");
      for (char c : std::string("4e2d")) {
        packet.keycode =
            static_cast<uint32_t>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
        packet.wch = c;
        packet.modifiers_down = 0;
        auto result =
            focused.key(first.pending, packet, ReplyPath::Composition);
        require(result && focused.confirm(first.pending, packet.request_id),
                "Focused Unicode edit failed");
        ++packet.request_id;
      }
      packet.keycode = 0x20;
      packet.wch = 0;
      auto committed = focused.key(first.pending, packet, ReplyPath::Selection);
      require(committed && committed->source.transition.at("commit") == "中" &&
                  committed->encoded &&
                  committed->encoded->packet.candidate_string[0] == 0x4e2d,
              "Focused Unicode commit/reply failed");
      require(focused.confirm(first.pending, packet.request_id),
              "Final delivery confirmation failed");
      const auto applied =
          focused.update_preferences(first.pending, focused_snapshot);
      require(applied && applied->at("deferred") == false,
              "Deferred configuration did not apply after composition ended");
      ++packet.request_id;
      packet.keycode = 'U';
      packet.wch = 'U';
      packet.modifiers_down = 1;
      require(focused.key(first.pending, packet, ReplyPath::Composition)
                  .has_value(),
              "Pending edit failed");
      auto second = *gate.begin(ticket, 78);
      const auto old_view = focused.view();
      require(!focused.key(first.pending, packet, ReplyPath::Composition) &&
                  !focused.confirm(first.pending, packet.request_id) &&
                  focused.view() == old_view,
              "Obsolete focus task reached Engine or confirmed output");
      require(!focused.update_preferences(first.pending, focused_snapshot) &&
                  focused.view() == old_view,
              "Old focus configuration changed Engine state");
      require(focused.prepare(second.pending) &&
                  focused.view().at("editing_text") == "",
              "New activation retained old composition");
      require(!focused.cancel(first.pending),
              "Old cancellation cleared new prepared session");
      auto wrong_thread = std::async(std::launch::async, [&] {
        try {
          focused.prepare(second.pending);
        } catch (const std::logic_error &) {
          return true;
        }
        return false;
      });
      require(wrong_thread.get(),
              "Focused adapter accepted wrong queue thread");
      auto other = *gate.begin({99, {4, 5, 6}}, 79);
      require(focused.cancel(second.pending), "Previous owner cleanup failed");
      require(gate.with_pending(other.pending, [] {}),
              "Old owner cleanup invalidated new focus");
    }
    {
      using namespace msime::windows;
      FocusGate gate;
      FocusRouter router(gate, 2);
      FocusedSession first(gate, 42, options.dump());
      FocusedSession second(gate, 43, options.dump());
      PipeTicket a{42, {1, 2, 3}}, b{43, {4, 5, 6}};
      require(router.connected(a).accepted && router.connected(b).accepted,
              "Queue router registration failed");
      FanyImeNamedpipeData packet{};
      packet.client_id = 42;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 77;
      auto activation = router.dispatch(a, packet);
      require(activation.route && first.prepare(*activation.route),
              "Routed activation did not prepare Engine");
      require(gate.acknowledge(*activation.route, [] { return true; }) &&
                  router.confirmed(*activation.route),
              "Synthetic routed fence failed");
      packet.event_type = FanyImePipeEventType::KeyEvent;
      packet.request_id = 2;
      packet.keycode = 'U';
      packet.wch = 'U';
      packet.modifiers_down = 1;
      auto key_route = router.dispatch(a, packet);
      require(key_route.route &&
                  first.key(*key_route.route, packet, ReplyPath::Composition) &&
                  first.view().at("editing_text") == "U",
              "Routed key did not reach shared Engine");
      packet.client_id = 43;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 88;
      auto takeover = router.dispatch(b, packet);
      require(takeover.cleanup && first.cancel(*takeover.cleanup) &&
                  first.view().at("editing_text") == "" &&
                  takeover.route && second.prepare(*takeover.route),
              "Focus takeover failed to clean old Engine before preparation");
      require(!first.confirm(*key_route.route, 2),
              "Displaced pending reply was acknowledged");
      require(router.disconnected(b).accepted &&
                  second.cancel(*takeover.route),
              "Disconnected queue session cleanup failed");
    }
    {
      using namespace msime::windows;
      FocusGate gate;
      InputQueue queue(gate, 2, 8, options.dump());
      const auto run = [&](InputQueue::Task task) {
        auto completion = queue.submit(std::move(task));
        require(completion && completion->get() == InputTaskStatus::Completed,
                "Shared input queue task failed");
      };
      PipeTicket a{42, {1, 2, 3}}, b{43, {4, 5, 6}};
      FocusRoute activation;
      FanyImeNamedpipeData packet{};
      packet.client_id = 42;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 77;
      run([&](InputState &state) {
        require(state.connected(a).accepted && state.connected(b).accepted,
                "Worker session creation failed");
        activation = state.dispatch(a, packet);
        require(activation.route.has_value(), "Worker activation failed");
      });
      // Synthetic external I/O completion: never perform pipe I/O in a task.
      require(gate.acknowledge(*activation.route, [] { return true; }),
              "Worker queue synthetic fence failed");
      run([&](InputState &state) {
        require(state.confirmed(*activation.route), "Worker fence receipt failed");
      });
      packet.event_type = FanyImePipeEventType::KeyEvent;
      packet.request_id = 2;
      for (char c : std::string("U4e2d")) {
        packet.keycode = static_cast<uint32_t>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
        packet.wch = c;
        packet.modifiers_down = c == 'U' ? 1 : 0;
        run([&](InputState &state) {
          auto route = state.dispatch(a, packet);
          require(route.route.has_value(), "Worker key route missing");
          auto result = state.key(*route.route, packet, ReplyPath::Composition);
          require(result && result->encoded && *result->encoded,
                  "Worker composition failed");
        });
        run([&](InputState &state) {
          require(state.delivered(*activation.route, packet.request_id),
                  "Worker reply receipt failed");
        });
        ++packet.request_id;
      }
      packet.keycode = 0x20;
      packet.wch = 0;
      run([&](InputState &state) {
        auto result = state.key(*activation.route, packet, ReplyPath::Selection);
        require(result && result->source.transition.at("commit") == "中",
                "Dedicated worker Unicode commit failed");
        require(state.delivered(*activation.route, packet.request_id),
                "Worker commit receipt failed");
      });
      packet.client_id = 43;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 88;
      FocusRoute other;
      run([&](InputState &state) {
        other = state.dispatch(b, packet);
        require(other.activation && other.cleanup &&
                    !state.delivered(*activation.route, 2),
                "Worker focus takeover failed");
        require(!state.disconnected({42, {7, 2, 3}}).accepted,
                "Stale worker disconnect accepted");
      });
      queue.stop(); // Destroys both actual Rust/C++ sessions on the worker.
      require(!gate.with_pending(*other.route, [] {}),
              "Stopped worker retained focus authorization");
      InputQueue failing(gate, 1, 2, options.dump());
      packet.client_id = 42;
      auto failure = failing.submit([&](InputState &state) {
        require(state.connected(a).accepted, "Failure fixture registration failed");
        activation = state.dispatch(a, packet);
        require(activation.route.has_value(), "Failure fixture activation failed");
        throw std::runtime_error("Synthetic active-session failure");
      });
      require(failure && failure->get() == InputTaskStatus::Failed &&
                  !gate.with_pending(*activation.route, [] {}),
              "Failed task reported before withdrawing Engine authorization");
      failing.stop();
    }
    session_pump_tests(options.dump());
    session_worker_tests(options.dump());
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
      // Start a clean activation and select a real partial candidate from the
      // locked dictionary. Do not synthesize an Engine remainder for this test.
      session.deactivate(epoch);
      session.activate(++epoch);
      msime::windows::ReplyComposer composer(42, epoch);
      auto send = [&](uint32_t vk, uint32_t text,
                      msime::windows::ReplyPath path) {
        FanyImeNamedpipeData packet{};
        packet.event_type = FanyImePipeEventType::KeyEvent;
        packet.client_id = 42;
        packet.request_id = request++;
        packet.keycode = vk;
        packet.wch = static_cast<FanyImeWireChar>(text);
        const auto &pending = composer.dispatch(session, packet, epoch, path);
        auto copy = pending;
        auto unchanged = session.view();
        rejected([&] { composer.dispatch(session, packet, epoch, path); });
        require(session.view() == unchanged,
                "Pending-reply gate advanced Engine");
        require(!pending.encoded || static_cast<bool>(*pending.encoded),
                "Real reply cannot be encoded");
        composer.confirm_delivery(42, epoch, packet.request_id);
        return copy;
      };
      for (char c : std::string("nihao"))
        send(c - 'a' + 'A', c, msime::windows::ReplyPath::Composition);
      bool found = false;
      size_t slot = 0;
      for (size_t attempts = 0; attempts < 100; ++attempts) {
        auto current = session.view();
        for (size_t i = 0; i < current.at("candidates").size(); ++i) {
          if (current.at("candidates").at(i).at("text") == "你") {
            slot = i;
            found = true;
            break;
          }
        }
        if (found || current.at("page").get<size_t>() + 1 >=
                         current.at("page_count").get<size_t>())
          break;
        send(0x22, 0, msime::windows::ReplyPath::Composition);
      }
      require(found, "No real partial candidate in fixed dictionary");
      auto partial = send(static_cast<uint32_t>(0x61 + slot), 0,
                          msime::windows::ReplyPath::Selection);
      require(partial.source.transition.at("commit") == "你" &&
                  !partial.source.transition.at("view")
                       .at("editing_text")
                       .get<std::string>()
                       .empty(),
              "Fixture did not exercise a partial commit");
      require(partial.encoded->packet.msg_type ==
                      FanyImeReplyType::NeedToCreateWord &&
                  composer.selected_prefix() == "你",
              "Real partial prefix not retained");
      auto final = send(0x20, 0, msime::windows::ReplyPath::Selection);
      require(final.encoded->packet.msg_type == FanyImeReplyType::Normal &&
                  final.encoded->packet.candidate_string[0] == 0x4F60 &&
                  final.encoded->packet.candidate_string[1] == 0x597D &&
                  final.encoded->packet.candidate_string[2] == 0,
              "Legacy final reply lost or duplicated partial prefix");
      require(composer.selected_prefix().empty(),
              "Final reply retained stale prefix");
    }
    std::cout << "Windows Server boundary: shared session, routing and input "
                 "acceptance passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

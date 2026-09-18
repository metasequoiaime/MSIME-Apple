#include "../src/InputQueue.h"
#include "TestHostOptions.h"
#include <cassert>
#include <chrono>
using namespace msime::windows;
int main() {
  const auto root = std::filesystem::temp_directory_path() /
      ("msime-dedicated-english-" + std::to_string(
          std::chrono::steady_clock::now().time_since_epoch().count()));
  std::filesystem::create_directory(root);
  struct Cleanup {
    std::filesystem::path root;
    ~Cleanup() { std::error_code ec; std::filesystem::remove_all(root, ec); }
  } cleanup{root};
  auto options = test_host_options(root);
  // 默认输入状态 picks the state a new focus session starts in, and the host
  // applies it as its own English passthrough. It must not start the Engine in
  // dedicated English, whose candidates are English words and which the CN/EN
  // switch cannot leave.
  options["preferences"]["default_ime_mode"] = "english";
  const auto serialized = options.dump();
  {
    FocusGate gate;
    InputState state(gate, 2, serialized);
    const PipeTicket ticket{42, {1, 2, 3}};
    assert(state.connected(ticket).accepted);
    // Maintenance reaches an idle session without a candidate snapshot.
    assert(state.reset_cache());
    FanyImeNamedpipeData packet{};
    packet.client_id = 42;
    packet.event_type = FanyImePipeEventType::ClientActivated;
    packet.request_id = 77;
    const auto route = state.dispatch(ticket, packet);
    assert(route.route);
    const auto lease = *route.route;
    assert(!state.dedicated_english(lease, true));
    assert(gate.acknowledge(lease, [] { return true; }));
    assert(state.confirmed(lease));
    const auto initial = state.dedicated_english(lease, false);
    assert(initial && initial->at("dedicated_english") == false);
    auto stale = lease;
    ++stale.token;
    assert(!state.dedicated_english(stale, true));
    ++stale.transport.generations[0];
    assert(!state.dedicated_english(stale, false));
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.request_id = 2;
    packet.keycode = 'A';
    packet.wch = 'a';
    auto pending = state.key(lease, packet, ReplyPath::Composition);
    assert(pending);
    assert(!state.dedicated_english(lease, true));
    assert(state.delivered(lease, packet.request_id));
    // The letter opens a pinyin composition instead of being answered with
    // English words.
    const auto typed = state.dedicated_english(lease, false);
    assert(typed && typed->at("dedicated_english") == false);
    assert(typed->at("editing_text") == "a");
    // Exit is a no-op while the mode is off: it neither cancels the
    // composition nor moves the Engine on.
    const auto idle = state.dedicated_english(lease, true);
    assert(idle && idle->at("dedicated_english") == false);
    assert(idle->at("editing_text") == "a");
    assert(idle->at("generation") == typed->at("generation"));
    assert(state.quiesce_dictionaries() == 1);
    assert(!state.dedicated_english(lease, true));
  }
  // A fresh session starts in Chinese as well; the saved default decides the
  // host's passthrough and never the Engine's English candidates.
  ServerSession fresh(43, serialized);
  fresh.activate(1);
  assert(fresh.dedicated_english(1, false).at("dedicated_english") == false);
  assert(options["preferences"]["default_ime_mode"] == "english");
}

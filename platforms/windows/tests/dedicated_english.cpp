#include "../InputQueue.h"
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
  options["preferences"]["default_ime_mode"] = "english";
  const auto serialized = options.dump();
  {
    FocusGate gate;
    InputState state(gate, 2, serialized);
    const PipeTicket ticket{42, {1, 2, 3}};
    assert(state.connected(ticket).accepted);
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
    assert(initial && initial->at("dedicated_english") == true);
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
    const auto exited = state.dedicated_english(lease, true);
    assert(exited && exited->at("dedicated_english") == false);
    assert(exited->at("editing_text") == "" && exited->at("candidates").empty());
    const auto again = state.dedicated_english(lease, true);
    assert(again && again->at("generation") == exited->at("generation"));
    assert(state.quiesce_dictionaries() == 1);
    assert(!state.dedicated_english(lease, true));
  }
  // A fresh session still honors the saved default; exit was runtime-only.
  ServerSession fresh(43, serialized);
  fresh.activate(1);
  assert(fresh.dedicated_english(1, false).at("dedicated_english") == true);
  assert(options["preferences"]["default_ime_mode"] == "english");
}

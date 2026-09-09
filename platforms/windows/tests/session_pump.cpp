#include "SessionPump.h"
#include <atomic>

using namespace msime::windows;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Session pump test failed");
}
class FixtureTransport final : public MainTransport {
public:
  PipeTicket ticket{42, {1, 2, 3}};
  std::atomic<bool> open{true};
  std::vector<FanyImeNamedpipeData> packets;
  std::vector<std::pair<uint32_t, std::vector<uint8_t>>> writes;
  size_t next = 0;
  size_t fail_write = 0;
  const std::thread::id io_thread = std::this_thread::get_id();
  bool current(const PipeTicket &value) override {
    return open && same_ticket(ticket, value);
  }
  std::optional<FanyImeNamedpipeData> read(const PipeTicket &value) override {
    require(std::this_thread::get_id() == io_thread);
    if (!current(value) || next == packets.size())
      return std::nullopt;
    return packets[next++];
  }
  bool send(const PipeTicket &value, uint32_t role,
            const std::vector<uint8_t> &frame) override {
    require(std::this_thread::get_id() == io_thread);
    if (!current(value))
      return false;
    writes.emplace_back(role, frame);
    return writes.size() != fail_write;
  }
  void close(const PipeTicket &value) noexcept override {
    if (same_ticket(ticket, value))
      open = false;
  }
  FixtureTransport() {
    FanyImeNamedpipeData packet{};
    packet.client_id = ticket.client;
    packet.event_type = FanyImePipeEventType::ClientActivated;
    packet.request_id = 77;
    packets.push_back(packet);
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.request_id = 2;
    for (char c : std::string("U4e2d")) {
      packet.keycode =
          static_cast<uint32_t>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
      packet.wch = c;
      packet.modifiers_down = c == 'U' ? 1 : 0;
      packets.push_back(packet);
      ++packet.request_id;
    }
    packet.keycode = 0x20;
    packet.wch = 0;
    packets.push_back(packet);
  }
};
} // namespace
void session_pump_tests(const std::string &options) {
  for (int mode = 0; mode < 6; ++mode) {
    FocusGate gate;
    InputQueue queue(gate, 2, 8, options);
    FixtureTransport transport;
    if (mode == 1)
      transport.fail_write = 1; // Initial focus fence.
    if (mode == 2)
      transport.fail_write = 3; // First reply may have been delivered.
    if (mode == 4)
      transport.packets[1].client_id = 43; // Reject even a faulty transport.
    if (mode == 5)
      transport.packets.resize(2);
    if (mode == 0) {
      auto repeated = transport.packets.front();
      repeated.event_type = FanyImePipeEventType::ClientHello;
      transport.packets.push_back(repeated);
    }
    size_t keys = 0;
    std::optional<FocusLease> takeover;
    std::optional<FocusLease> lease;
    SessionPump pump(
        transport, queue, gate,
        [&](InputState &state, const FocusLease &focus,
            const FanyImeNamedpipeData &packet) {
          require(std::this_thread::get_id() != transport.io_thread);
          ++keys;
          // Only this fixed synthetic Unicode sequence uses this test plan.
          // This is not a VK-only production TSF dispatch implementation.
          auto result =
              state.key(focus, packet,
                        packet.keycode == 0x20 ? ReplyPath::Selection
                                               : ReplyPath::Composition);
          if (mode == 3 && result)
            ++result->source.request_id;
          if (mode == 5 && result) {
            PipeTicket other{43, {4, 5, 6}};
            require(state.connected(other).accepted);
            auto activated = transport.packets.front();
            activated.client_id = 43;
            activated.request_id = 88;
            takeover = state.dispatch(other, activated).route;
          }
          return result;
        },
        [&](const FocusRoute &route, const FanyImeNamedpipeData &) {
          require(std::this_thread::get_id() != transport.io_thread);
          lease = route.route;
          return true;
        });
    const auto result = pump.run(transport.ticket);
    require(!transport.open);
    if (lease)
      require(!gate.with_active(*lease, [] {}));
    if (mode == 0) {
      require(result == PumpResult::Disconnected && keys == 6 &&
              transport.next == 8 && transport.writes.size() == 13);
      const auto fence = *focus_ready_bytes(77);
      require(transport.writes[0].first == FanyImePipeRole::ToTsfWorkerThread &&
              transport.writes[0].second == fence);
      for (size_t i = 0; i < 6; ++i) {
        require(transport.writes[1 + 2 * i].second == fence &&
                transport.writes[1 + 2 * i].first ==
                    FanyImePipeRole::ToTsfWorkerThread);
        require(transport.writes[2 + 2 * i].first == FanyImePipeRole::ToTsf &&
                transport.writes[2 + 2 * i].second.size() ==
                    sizeof(FanyImeNamedpipeDataToTsf));
      }
      const auto expected = *wire_bytes(candidate_commit(7, "中"));
      require(transport.writes.back().second ==
              std::vector<uint8_t>(expected.begin(), expected.end()));
    } else if (mode == 1) {
      require(result == PumpResult::WriteFailed && keys == 0 &&
              transport.next == 1);
    } else if (mode == 2) {
      require(result == PumpResult::WriteFailed && keys == 1 &&
              transport.next == 2 && transport.writes.size() == 3);
    } else if (mode == 3) {
      require(result == PumpResult::DispatchFailed && keys == 1 &&
              transport.writes.size() == 2);
    } else if (mode == 4) {
      require(result == PumpResult::DispatchFailed && keys == 0 &&
              transport.writes.size() == 1);
    } else {
      require(result == PumpResult::Disconnected && keys == 1 &&
              transport.writes.size() == 2 && takeover &&
              gate.with_pending(*takeover, [] {}));
    }
    queue.stop();
  }
  {
    FocusGate gate;
    InputQueue queue(gate, 1, 1, options);
    FixtureTransport transport;
    SessionPump pump(
        transport, queue, gate,
        [](InputState &, const FocusLease &, const FanyImeNamedpipeData &)
            -> std::optional<PendingReply> { return std::nullopt; },
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    auto rejected = queue.submit([&](InputState &) {
      require(pump.run(transport.ticket) == PumpResult::QueueUnavailable);
    });
    require(rejected && rejected->get() == InputTaskStatus::Completed);
    require(transport.open); // Rejected self-wait did not touch transport.
    queue.stop();
    require(pump.run(transport.ticket) == PumpResult::QueueUnavailable &&
            !transport.open && transport.writes.empty());
  }
}

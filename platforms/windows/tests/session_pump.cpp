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
  {
    FanyImeNamedpipeData packet{};
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.keycode = '1';
    packet.wch = '1';
    require(edit_kind(packet, "none", true) == EditKind::None);
    require(edit_kind(packet, "unicode", true) == EditKind::Character);
    packet.modifiers_down = 1;
    packet.wch = '+';
    require(edit_kind(packet, "unicode", true) == EditKind::None);
    packet.keycode = 0xBB;
    require(edit_kind(packet, "unicode", true) == EditKind::Character);
    require(edit_kind(packet, "none", true) == EditKind::None);
    packet.keycode = 0x20;
    require(edit_kind(packet, "unicode", true) == EditKind::None);
    packet.keycode = 'A';
    packet.wch = 'A';
    packet.modifiers_down = 2;
    require(edit_kind(packet, "none", true) == EditKind::None);
    packet.modifiers_down = 0;
    require(edit_kind(packet, "unknown", true) == EditKind::None);
    packet.keycode = 0xDE;
    packet.wch = '\'';
    require(edit_kind(packet, "none", false) == EditKind::None);
    require(edit_kind(packet, "none", true) == EditKind::Character);
  }
  for (int mode = 0; mode < 4; ++mode) {
    FocusGate gate;
    InputQueue queue(gate, 2, 8, options);
    FixtureTransport transport;
    transport.packets.pop_back(); // Editing only; no candidate commit.
    auto packet = transport.packets.back();
    packet.wch = 0;
    packet.modifiers_down = 0;
    for (uint32_t key : {0x25, 0x27, 0x08, 0x08, 0x08, 0x08, 0x08}) {
      packet.keycode = key;
      ++packet.request_id;
      transport.packets.push_back(packet);
    }
    const bool uiless = mode >= 2;
    const auto style = mode % 2 ? TsfPreeditStyle::Pinyin : TsfPreeditStyle::Local;
    if (uiless)
      for (size_t i = 1; i < transport.packets.size(); ++i)
        transport.packets[i].modifiers_down |= FanyImePipeFlags::UiLess;
    size_t keys = 0;
    SessionPump pump(
        transport, queue, gate,
        [&](InputState &state, const FocusLease &focus, const FanyImeNamedpipeData &key) {
          auto result = state.edit(focus, key, style);
          require(result.has_value());
          ++keys;
          const bool reply = uiless || (style == TsfPreeditStyle::Pinyin &&
                                       keys != 6 && keys != 7 && keys != 12);
          require(result->encoded.has_value() == reply);
          require(result->source.reply_expected == reply);
          if (result->encoded)
            require(result->encoded->packet.msg_type ==
                    (uiless ? FanyImeReplyType::UiLessComposition : FanyImeReplyType::Preedit));
          if (keys == 12)
            require(result->source.transition.at("view").at("editing_text") == "");
          return result;
        }, [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    require(pump.run(transport.ticket) == PumpResult::Disconnected && keys == 12);
    require(transport.writes.size() == 13 + (uiless ? 12 : mode == 1 ? 9 : 0));
    queue.stop();
  }
  for (auto event : {FanyImePipeEventType::PuncSwitch,
                    FanyImePipeEventType::StatusSnapshot,
                    FanyImePipeEventType::FocusRestored}) {
    FocusGate gate;
    InputQueue queue(gate, 2, 8, options);
    FixtureTransport transport;
    transport.packets.resize(1);
    auto status = transport.packets.front();
    status.event_type = event;
    status.keycode = event == FanyImePipeEventType::PuncSwitch ? 0 : 1;
    transport.packets.push_back(status);
    auto punctuation = transport.packets.front();
    punctuation.event_type = FanyImePipeEventType::KeyEvent;
    punctuation.request_id = 2;
    punctuation.keycode = 0xBC;
    punctuation.wch = ',';
    transport.packets.push_back(punctuation);
    status.keycode = 1;
    status.pinyin_length = event == FanyImePipeEventType::PuncSwitch ? 0 : 1;
    transport.packets.push_back(status);
    ++punctuation.request_id;
    transport.packets.push_back(punctuation);
    size_t keys = 0;
    SessionPump pump(
        transport, queue, gate,
        [&](InputState &state, const FocusLease &focus,
            const FanyImeNamedpipeData &packet) {
          auto reply = state.key(focus, packet, ReplyPath::Punctuation);
          require(reply.has_value());
          if (++keys == 1)
            require(reply->source.transition.at("handled") == false &&
                    reply->source.transition.at("commit").is_null());
          else
            require(reply->source.transition.at("commit") == "，");
          return reply;
        },
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    require(pump.run(transport.ticket) == PumpResult::Disconnected && keys == 2);
    queue.stop();
  }
  for (auto event : {FanyImePipeEventType::StatusSnapshot,
                     FanyImePipeEventType::IMESwitch,
                     FanyImePipeEventType::FocusRestored}) {
    FocusGate gate;
    InputQueue queue(gate, 2, 8, options);
    FixtureTransport transport;
    const auto original = transport.packets;
    auto status = original.front();
    status.event_type = event;
    status.keycode = 0;
    transport.packets.insert(transport.packets.end() - 1, status);
    transport.packets.insert(transport.packets.end() - 1, status);
    // Closed mode must also suppress a fresh Unicode-mode trigger.
    transport.packets.push_back(original[1]);
    status.keycode = event == FanyImePipeEventType::IMESwitch ? 9 : 1;
    transport.packets.push_back(status);
    transport.packets.insert(transport.packets.end(), original.begin() + 1,
                             original.end());
    size_t keys = 0;
    size_t notifications = 0;
    SessionPump pump(
        transport, queue, gate,
        [&](InputState &state, const FocusLease &focus,
            const FanyImeNamedpipeData &packet) {
          ++keys;
          auto reply =
              state.key(focus, packet,
                        packet.keycode == 0x20 ? ReplyPath::Selection
                                               : ReplyPath::Composition);
          require(reply.has_value());
          const auto &transition = reply->source.transition;
          if (keys == 5)
            require(transition.at("view").at("editing_text") == "U4e2d");
          if (keys == 6 || keys == 7)
            require(transition.at("commit").is_null() &&
                    transition.at("handled") == false &&
                    transition.at("view").at("editing_text") == "");
          if (keys == 13)
            require(transition.at("commit") == "中");
          return reply;
        },
        [&](const FocusRoute &, const FanyImeNamedpipeData &packet) {
          if (packet.event_type == event)
            ++notifications;
          return true;
        });
    require(pump.run(transport.ticket) == PumpResult::Disconnected);
    require(keys == 13 && notifications == 3);
    queue.stop();
  }
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

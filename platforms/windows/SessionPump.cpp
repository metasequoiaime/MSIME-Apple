#include "SessionPump.h"

namespace msime::windows {
SessionPump::SessionPump(MainTransport &transport, InputQueue &input,
                         FocusGate &focus, KeyHandler key, EventHandler event)
    : transport_(transport), input_(input), focus_(focus), key_(std::move(key)),
      event_(std::move(event)) {
  if (!key_ || !event_)
    throw std::invalid_argument("Missing Windows dispatch handlers");
}
bool SessionPump::enqueue(InputQueue::Task task) {
  auto completion = input_.submit(std::move(task));
  return completion && completion->get() == InputTaskStatus::Completed;
}
void SessionPump::cleanup(const PipeTicket &ticket) noexcept {
  focus_.invalidate(ticket);
  transport_.close(ticket);
  try {
    if (enqueue([ticket](InputState &state) { state.disconnected(ticket); }))
      return;
  } catch (...) {
  }
  // No room for mandatory cleanup: stop the shared worker so it releases all
  // thread-local sessions. The owner must then stop other transport pumps too.
  input_.request_stop();
}
PumpResult SessionPump::run(const PipeTicket &ticket) {
  if (input_.on_worker_thread())
    return PumpResult::QueueUnavailable;
  struct Cleanup {
    SessionPump &pump;
    const PipeTicket &ticket;
    ~Cleanup() { pump.cleanup(ticket); }
  } cleanup_guard{*this, ticket};
  try {
    bool connected = false;
    if (!enqueue([&, ticket](InputState &state) {
          if (transport_.current(ticket))
            connected = state.connected(ticket).accepted;
        }))
      return PumpResult::QueueUnavailable;
    if (!connected)
      return PumpResult::Disconnected;
    while (auto packet = transport_.read(ticket)) {
      if (!valid_main_frame(*packet, ticket.client))
        return PumpResult::DispatchFailed;
      FocusRoute route;
      if (!enqueue([&, ticket, packet = *packet](InputState &state) {
            if (transport_.current(ticket))
              route = state.dispatch(ticket, packet);
          }))
        return PumpResult::QueueUnavailable;
      if (!route.accepted)
        continue;
      if (packet->event_type == FanyImePipeEventType::ClientHello)
        continue;
      if (route.route && route.fence) {
        const auto bytes = focus_ready_bytes(route.route->token);
        if (!bytes)
          return PumpResult::DispatchFailed;
        bool sent = false;
        bool attempted = false;
        if (route.activation) {
          sent = focus_.acknowledge(*route.route, [&] {
            attempted = true;
            return transport_.send(ticket, FanyImePipeRole::ToTsfWorkerThread,
                                   *bytes);
          });
        } else {
          focus_.with_active(*route.route, [&] {
            attempted = true;
            sent = transport_.send(ticket, FanyImePipeRole::ToTsfWorkerThread,
                                   *bytes);
          });
        }
        if (!attempted)
          continue; // Ordinary focus displacement is not a broken transport.
        if (!sent)
          return PumpResult::WriteFailed;
        bool confirmed = false;
        if (!enqueue([&, lease = *route.route](InputState &state) {
              confirmed = state.confirmed(lease);
            }))
          return PumpResult::QueueUnavailable;
        if (!confirmed)
          continue;
      }
      if (packet->event_type != FanyImePipeEventType::KeyEvent) {
        bool handled = false;
        bool eligible = false;
        if (!enqueue([&, route, packet = *packet](InputState &state) {
              if (!transport_.current(ticket))
                return;
              if (route.route &&
                  (packet.event_type == FanyImePipeEventType::IMESwitch ||
                   packet.event_type == FanyImePipeEventType::StatusSnapshot ||
                   packet.event_type == FanyImePipeEventType::FocusRestored) &&
                  !state.synchronize_input_mode(*route.route, packet))
                return;
              if (route.route)
                eligible = focus_.with_active(
                    *route.route, [&] { handled = event_(route, packet); });
              else {
                eligible = true;
                handled = event_(route, packet);
              }
            }))
          return PumpResult::QueueUnavailable;
        if (!eligible)
          continue;
        if (!handled)
          return PumpResult::DispatchFailed;
        continue;
      }
      if (!route.route)
        return PumpResult::DispatchFailed;
      std::optional<PendingReply> reply;
      if (!enqueue(
              [&, lease = *route.route, packet = *packet](InputState &state) {
                if (transport_.current(ticket))
                  reply = key_(state, lease, packet);
              }))
        return PumpResult::QueueUnavailable;
      if (!focus_.with_active(*route.route, [] {}))
        continue;
      if (!reply || reply->source.client_id != ticket.client ||
          reply->source.activation_epoch != route.route->epoch ||
          reply->source.request_id != packet->request_id ||
          (reply->encoded &&
           reply->encoded->packet.request_id != packet->request_id))
        return PumpResult::DispatchFailed;
      if (reply->encoded) {
        const auto bytes = wire_bytes(*reply->encoded);
        if (!bytes)
          return PumpResult::DispatchFailed;
        bool sent = false;
        const bool eligible = focus_.with_active(*route.route, [&] {
          sent = transport_.send(
              ticket, FanyImePipeRole::ToTsf,
              std::vector<uint8_t>(bytes->begin(), bytes->end()));
        });
        if (!eligible)
          continue;
        if (!sent)
          return PumpResult::WriteFailed;
      }
      bool delivered = false;
      if (!enqueue([&, lease = *route.route,
                    request = reply->source.request_id](InputState &state) {
            delivered = state.delivered(lease, request);
          }))
        return PumpResult::QueueUnavailable;
      if (!delivered && focus_.with_active(*route.route, [] {}))
        return PumpResult::DispatchFailed;
    }
    return PumpResult::Disconnected;
  } catch (...) {
    // No input/path-bearing diagnostics and no retry after uncertain output.
    return PumpResult::DispatchFailed;
  }
}
} // namespace msime::windows

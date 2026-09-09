#pragma once
#include "InputQueue.h"
#include "MainTransport.h"

namespace msime::windows {
enum class PumpResult {
  Disconnected,
  QueueUnavailable,
  DispatchFailed,
  WriteFailed
};
class SessionPump final {
public:
  // Both handlers execute on the input queue, never the pump's I/O worker.
  // Key must use the real TSF dispatch context to choose a ReplyPath and call
  // state.key once. Events publishes UI/mode work tagged with its lease; false
  // aborts routing. Active event callbacks hold the focus lock: no gate
  // reentry, I/O, or Engine calls. Cleanup-only events cannot affect another
  // owner's UI.
  using KeyHandler = std::function<std::optional<PendingReply>(
      InputState &, const FocusLease &, const FanyImeNamedpipeData &)>;
  using EventHandler =
      std::function<bool(const FocusRoute &, const FanyImeNamedpipeData &)>;
  SessionPump(MainTransport &transport, InputQueue &input, FocusGate &focus,
              KeyHandler key, EventHandler event);
  // One external I/O worker per current Main ticket; never call on input queue.
  // Owner bounds workers and cancels transport reads before joining them.
  // Dependencies/handlers outlive run(). No TSF registration or listener
  // startup.
  PumpResult run(const PipeTicket &ticket);

private:
  bool enqueue(InputQueue::Task task);
  void cleanup(const PipeTicket &ticket) noexcept;
  MainTransport &transport_;
  InputQueue &input_;
  FocusGate &focus_;
  KeyHandler key_;
  EventHandler event_;
};
} // namespace msime::windows

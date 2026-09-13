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
  struct Presentation {
    // Input queue, under active focus, after delivery and confirmation.
    // Copy bounded data only; no UI calls, I/O, Engine calls or gate reentry.
    std::function<void(const FocusLease &, const PendingReply &,
                       const FanyImeNamedpipeData &)> delivered;
    // Input queue after cleanup. Match the ticket before hiding an owner's UI.
    // Not guaranteed on queue failure: consumers must also clear on server stop
    // and revalidate the lease when rendering.
    std::function<void(const PipeTicket &)> disconnected;
    // Input queue after the original reply is confirmed. The callback may
    // submit bounded work to an external provider, but must not perform I/O.
    std::function<void(const FocusLease &, const PendingReply &)> online;
    std::function<void(const FocusLease &, const PendingReply &)> translation;
  };
  SessionPump(MainTransport &transport, InputQueue &input, FocusGate &focus,
              KeyHandler key, EventHandler event, Presentation presentation = {},
              std::shared_ptr<std::mutex> transactions = std::make_shared<std::mutex>());
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
  Presentation presentation_;
  std::shared_ptr<std::mutex> transactions_;
};
} // namespace msime::windows

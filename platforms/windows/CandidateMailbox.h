#pragma once
#include "CandidatePresentation.h"
#include <functional>

namespace msime::windows {
// Single latest value, not an unbounded per-key UI event queue. Publish only
// from the input queue's confirmed-delivery callback under the focus gate.
class CandidateMailbox final {
public:
  void delivered(const FocusLease &lease, const PendingReply &reply,
                 const FanyImeNamedpipeData &packet) {
    auto value = candidate_presentation(lease, reply, packet);
    std::lock_guard lock(mutex_);
    if (!stopped_) {
      latest_ = std::move(value);
      suppressed_ = false;
    }
  }
  // Input queue under the active focus gate, like delivered(). These visual
  // events never replay packet text into Engine or manufacture a composition.
  void event(const FocusLease &lease, const FanyImeNamedpipeData &packet) {
    std::lock_guard lock(mutex_);
    if (stopped_ || !latest_ || packet.client_id != lease.transport.client ||
        latest_->lease.epoch != lease.epoch ||
        latest_->lease.token != lease.token ||
        !same_ticket(latest_->lease.transport, lease.transport))
      return;
    switch (packet.event_type) {
    case FanyImePipeEventType::HideCandidateWnd:
      suppressed_ = true;
      break;
    case FanyImePipeEventType::ShowCandidateWnd:
      suppressed_ = (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0;
      [[fallthrough]];
    case FanyImePipeEventType::MoveCandidateWnd:
      latest_->x = packet.point[0];
      latest_->y = packet.point[1];
      break;
    }
  }
  void disconnected(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    if (latest_ && same_ticket(latest_->lease.transport, ticket))
      latest_.reset();
  }
  void stop() {
    std::lock_guard lock(mutex_);
    stopped_ = true;
    latest_.reset();
  }
  // External consumer only, never while holding the gate. No UI callbacks run
  // under either lock. The returned copy is valid at read time, not a grant to
  // perform a later candidate action without checking its identity again.
  std::optional<CandidatePresentation>
  snapshot(FocusGate &gate, bool wait = true,
           const std::function<bool(const FocusLease &)> &current = {}) {
    std::optional<FocusLease> lease;
    {
      std::unique_lock lock(mutex_, std::defer_lock);
      if (wait)
        lock.lock();
      else if (!lock.try_lock())
        return std::nullopt;
      if (latest_)
        lease = latest_->lease;
    }
    std::optional<CandidatePresentation> result;
    if (lease) {
      auto read = [&] {
        // Always gate -> mailbox, matching the producer's lock order. Fetch
        // the newest generation here, not the value observed before the gate.
        std::unique_lock lock(mutex_, std::defer_lock);
        if (wait)
          lock.lock();
        else if (!lock.try_lock())
          return;
        if (latest_ && latest_->lease.epoch == lease->epoch &&
            latest_->lease.token == lease->token &&
            same_ticket(latest_->lease.transport, lease->transport))
          result = latest_;
        if (result && suppressed_) {
          result->visible = false;
          result->preedit.clear();
          result->candidates.clear();
        }
        lock.unlock();
        // Validate transport while the focus lock still excludes pipe sends;
        // a post-lock check could start waiting behind the very next writer.
        if (result && current && !current(result->lease))
          result.reset();
      };
      if (wait)
        gate.with_active(*lease, read);
      else
        gate.try_with_active(*lease, read);
    }
    return result;
  }

private:
  std::mutex mutex_;
  bool stopped_ = false;
  bool suppressed_ = false;
  std::optional<CandidatePresentation> latest_;
};
} // namespace msime::windows

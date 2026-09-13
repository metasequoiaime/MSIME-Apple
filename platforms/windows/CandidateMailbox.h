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
  // Replace Engine-owned candidate data after an asynchronous cloud result.
  // Coordinates and the selected prefix belong to the existing presentation.
  void online(const FocusLease &lease, const nlohmann::json &view) {
    refresh_view(lease, view, true);
  }
  // Translation application keeps the same Engine generation; only the
  // candidate metadata changes.
  void translations(const FocusLease &lease, const nlohmann::json &view) {
    refresh_view(lease, view, false);
  }

private:
  void refresh_view(const FocusLease &lease, const nlohmann::json &view,
                    bool require_new_generation) {
    std::lock_guard lock(mutex_);
    try {
      if (stopped_ || !latest_ || latest_->lease.epoch != lease.epoch ||
          latest_->lease.token != lease.token ||
          !same_ticket(latest_->lease.transport, lease.transport))
        return;
      if (view.at("session").get<uint64_t>() != latest_->session ||
          (require_new_generation &&
           view.at("generation").get<uint64_t>() <= latest_->generation))
        return;
      const auto text = view.at("preedit").get<std::string>();
      if (latest_->preedit.size() < text.size() ||
          latest_->preedit.compare(latest_->preedit.size() - text.size(),
                                   text.size(), text) != 0)
        return;
      const auto prefix = latest_->preedit.substr(
          0, latest_->preedit.size() - text.size());
      latest_ = candidate_presentation_from_view(lease, view, latest_->x,
                                                 latest_->y, prefix);
    } catch (...) {
      // Provider data is optional; malformed/stale projections are ignored.
    }
  }

public:
  // Input queue under the active focus gate, like delivered(). Hide follows
  // successful Engine cancellation; show/move never manufacture composition.
  void event(const FocusLease &lease, const FanyImeNamedpipeData &packet) {
    std::lock_guard lock(mutex_);
    if (stopped_ || !latest_ || packet.client_id != lease.transport.client ||
        latest_->lease.epoch != lease.epoch ||
        latest_->lease.token != lease.token ||
        !same_ticket(latest_->lease.transport, lease.transport))
      return;
    switch (packet.event_type) {
    case FanyImePipeEventType::ClientActivated:
      if (packet.keycode != 0)
        suppressed_ = true;
      break;
    case FanyImePipeEventType::IMESwitch:
    case FanyImePipeEventType::StatusSnapshot:
    case FanyImePipeEventType::FocusRestored:
      // Input mode has already been synchronized on the input queue. An
      // English notification cancels composition; re-enabling must not revive
      // the old projection. A mode request alone is not a notification.
      if (packet.keycode != 0)
        break;
      [[fallthrough]];
    case FanyImePipeEventType::HideCandidateWnd:
      suppressed_ = true;
      latest_->visible = false;
      latest_->preedit.clear();
      latest_->candidates.clear();
      break;
    case FanyImePipeEventType::ShowCandidateWnd:
      suppressed_ = (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0;
      [[fallthrough]];
    case FanyImePipeEventType::MoveCandidateWnd:
      // The host may take over candidate rendering without another key or
      // Show event. A move can suppress display, never revive hidden content.
      if ((packet.modifiers_down & FanyImePipeFlags::UiLess) != 0)
        suppressed_ = true;
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
  // The optional identity validator runs under the gate and must not reenter;
  // non-waiting consumers must supply a non-waiting validator as well.
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
        // Keep identity validation in the same active-focus scope. The
        // validator must also avoid waiting on independent handshake I/O.
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

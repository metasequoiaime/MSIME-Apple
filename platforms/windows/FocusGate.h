#pragma once
#include "PipeTicket.h"
#include <limits>
#include <mutex>
#include <optional>
#include <utility>

namespace msime::windows {
struct FocusLease {
  PipeTicket transport;
  uint64_t epoch = 0;
  uint64_t token = 0;
};
struct FocusChange {
  std::optional<FocusLease> previous;
  FocusLease pending;
};
// Mechanism only: caller authenticates lifecycle events and chooses when an
// activation changes. Engine composition still belongs to ServerSession.
class FocusGate final {
public:
  std::optional<FocusChange> begin(const PipeTicket &ticket, uint64_t token) {
    std::lock_guard lock(mutex_);
    if (!ticket.client || !token)
      return std::nullopt;
    for (auto generation : ticket.generations)
      if (!generation)
        return std::nullopt;
    if (next_epoch_ == std::numeric_limits<uint64_t>::max()) {
      current_.reset();
      ready_ = false;
      return std::nullopt;
    }
    FocusChange change{current_, {ticket, ++next_epoch_, token}};
    current_ = change.pending;
    ready_ = false;
    return change;
  }
  // Prepare the queue-owned Engine session before scheduling its worker fence.
  template <typename Action>
  bool with_pending(const FocusLease &lease, Action &&action) {
    std::lock_guard lock(mutex_);
    if (!matches(lease) || ready_)
      return false;
    std::forward<Action>(action)();
    return true;
  }
  // Writer performs the ordered worker fence and returns true only on complete
  // delivery. Do not re-enter this gate from either callback. The transport
  // registry must revalidate the ticket while writing. Uncertain writes fail.
  template <typename Writer>
  bool acknowledge(const FocusLease &lease, Writer &&writer) {
    std::lock_guard lock(mutex_);
    if (!matches(lease) || ready_)
      return false;
    try {
      if (std::forward<Writer>(writer)()) {
        ready_ = true;
        return true;
      }
    } catch (...) {
      current_.reset();
      ready_ = false;
      throw;
    }
    current_.reset();
    ready_ = false;
    return false;
  }
  // Check AND execute under the same focus lock so a new activation cannot
  // overtake a send after its check. Actions must be short/bounded. Input-queue
  // tasks must separately obey ServerSession's thread affinity.
  template <typename Action>
  bool with_active(const FocusLease &lease, Action &&action) {
    std::lock_guard lock(mutex_);
    if (!matches(lease) || !ready_)
      return false;
    std::forward<Action>(action)();
    return true;
  }
  bool deactivate(const FocusLease &lease) {
    std::lock_guard lock(mutex_);
    if (!matches(lease))
      return false;
    current_.reset();
    ready_ = false;
    return true;
  }
  bool invalidate(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    if (!current_ || !same_ticket(current_->transport, ticket))
      return false;
    current_.reset();
    ready_ = false;
    return true;
  }

private:
  bool matches(const FocusLease &lease) const {
    return current_ && current_->epoch == lease.epoch &&
           current_->token == lease.token &&
           same_ticket(current_->transport, lease.transport);
  }
  std::mutex mutex_;
  uint64_t next_epoch_ = 0;
  std::optional<FocusLease> current_;
  bool ready_ = false;
};
} // namespace msime::windows

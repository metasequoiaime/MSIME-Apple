#pragma once
#include "PipeTicket.h"
#include <chrono>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <optional>
#include <stdexcept>

namespace msime::windows {
// Handshake completion mailbox. No cancellation, Engine work or pipe I/O under
// its lock. A false push lets PipeIntake remove the matching registration.
class RegistrationInbox final {
public:
  explicit RegistrationInbox(size_t capacity) : capacity_(capacity) {
    if (!capacity || capacity > 1024)
      throw std::invalid_argument("Invalid registration inbox capacity");
  }
  bool push(const PipeTicket &ticket) {
    if (!ticket.client)
      return false;
    for (auto generation : ticket.generations)
      if (!generation)
        return false;
    std::lock_guard lock(mutex_);
    if (closed_ || tickets_.size() == capacity_)
      return false;
    tickets_.push_back(ticket);
    ready_.notify_one();
    return true;
  }
  std::optional<PipeTicket> take_for(std::chrono::milliseconds timeout) {
    std::unique_lock lock(mutex_);
    ready_.wait_for(lock, timeout,
                    [&] { return closed_ || !tickets_.empty(); });
    if (closed_ || tickets_.empty())
      return std::nullopt;
    auto ticket = tickets_.front();
    tickets_.pop_front();
    return ticket;
  }
  void close() {
    std::lock_guard lock(mutex_);
    closed_ = true;
    tickets_.clear(); // Service shutdown owns closing all these registrations.
    ready_.notify_all();
  }
  bool closed() const {
    std::lock_guard lock(mutex_);
    return closed_;
  }

private:
  size_t capacity_;
  mutable std::mutex mutex_;
  std::condition_variable ready_;
  std::deque<PipeTicket> tickets_;
  bool closed_ = false;
};
} // namespace msime::windows

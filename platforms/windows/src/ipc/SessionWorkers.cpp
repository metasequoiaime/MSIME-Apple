#include "SessionWorkers.h"

namespace msime::windows {
namespace {
thread_local const SessionWorkers *active_workers = nullptr;
struct WorkerScope {
  explicit WorkerScope(const SessionWorkers *workers) {
    active_workers = workers;
  }
  ~WorkerScope() { active_workers = nullptr; }
};
} // namespace
SessionWorkers::SessionWorkers(MainTransport &transport, InputQueue &input,
                               FocusGate &focus, size_t capacity,
                               SessionPump::KeyHandler key,
                               SessionPump::EventHandler event,
                               SessionPump::Presentation presentation,
                               std::shared_ptr<std::mutex> transactions)
    : transport_(transport), input_(input),
      pump_(transport, input, focus, std::move(key), std::move(event),
            std::move(presentation), std::move(transactions)) {
  if (!capacity || capacity > 64)
    throw std::invalid_argument("Invalid session worker capacity");
  if (input_.on_worker_thread())
    throw std::logic_error(
        "Session workers require an external control thread");
  slots_.resize(capacity);
  workers_.reserve(capacity);
  try {
    for (size_t i = 0; i < capacity; ++i)
      workers_.emplace_back(&SessionWorkers::run, this, i);
  } catch (...) {
    request_stop();
    for (auto &worker : workers_)
      worker.join();
    throw;
  }
}
SessionWorkers::~SessionWorkers() { stop(); }
bool SessionWorkers::submit(const PipeTicket &ticket) {
  if (input_.on_worker_thread() || active_workers == this)
    throw std::logic_error("Session admission requires a control thread");
  bool valid = ticket.client != 0;
  for (auto generation : ticket.generations)
    valid = valid && generation != 0;
  if (valid)
    valid = transport_.current(ticket);
  std::optional<PipeTicket> replaced_active;
  std::optional<PipeTicket> replaced_pending;
  bool accepted = false;
  {
    std::lock_guard lock(mutex_);
    if (valid && !stats_.stopping) {
      Slot *chosen = nullptr;
      for (auto &slot : slots_)
        if (slot.client == ticket.client) {
          chosen = &slot;
          break;
        }
      if (!chosen)
        for (auto &slot : slots_)
          if (!slot.client) {
            chosen = &slot;
            break;
          }
      if (chosen) {
        const auto latest = chosen->pending ? chosen->pending : chosen->active;
        if (latest && same_ticket(*latest, ticket))
          return true;
        if (latest)
          for (size_t i = 0; i < 3; ++i)
            valid = valid && ticket.generations[i] >= latest->generations[i];
        if (valid) {
          replaced_active = chosen->active;
          replaced_pending = chosen->pending;
          chosen->client = ticket.client;
          chosen->pending = ticket;
          accepted = true;
        }
      }
    }
    if (!accepted)
      ++stats_.rejected;
  }
  // Never hold the slot lock while cancelling transport or waiting for the
  // pump's queue cleanup. Exact tickets cannot close a newer registration.
  if (replaced_active)
    transport_.close(*replaced_active);
  if (replaced_pending)
    transport_.close(*replaced_pending);
  if (!accepted)
    transport_.close(ticket);
  else
    ready_.notify_all();
  return accepted;
}
void SessionWorkers::request_stop() {
  std::array<PipeTicket, 128> closing{};
  size_t count = 0;
  {
    std::lock_guard lock(mutex_);
    if (stats_.stopping)
      return;
    stats_.stopping = true;
    for (auto &slot : slots_) {
      if (slot.active)
        closing[count++] = *slot.active;
      if (slot.pending)
        closing[count++] = *slot.pending;
      slot.pending.reset();
    }
  }
  for (size_t i = 0; i < count; ++i)
    transport_.close(closing[i]);
  ready_.notify_all();
}
void SessionWorkers::stop() {
  if (input_.on_worker_thread() || active_workers == this)
    throw std::logic_error("Session workers cannot join a dependent thread");
  std::lock_guard lock(stop_mutex_);
  request_stop();
  for (auto &worker : workers_)
    if (worker.joinable())
      worker.join();
}
SessionWorkerStats SessionWorkers::stats() const {
  std::lock_guard lock(mutex_);
  auto result = stats_;
  for (const auto &slot : slots_) {
    result.active += slot.active.has_value();
    result.pending += slot.pending.has_value();
  }
  return result;
}
void SessionWorkers::run(size_t index) {
  WorkerScope scope(this);
  for (;;) {
    PipeTicket ticket;
    {
      std::unique_lock lock(mutex_);
      auto &slot = slots_[index];
      ready_.wait(lock,
                  [&] { return stats_.stopping || slot.pending.has_value(); });
      if (stats_.stopping)
        return;
      ticket = *slot.pending;
      slot.pending.reset();
      slot.active = ticket;
    }
    const auto result = pump_.run(ticket);
    {
      std::lock_guard lock(mutex_);
      auto &slot = slots_[index];
      slot.active.reset();
      if (!slot.pending)
        slot.client = 0;
      ++stats_.finished;
      if (result != PumpResult::Disconnected)
        ++stats_.failed;
    }
    if (result == PumpResult::QueueUnavailable || !input_.stats().accepting)
      request_stop();
  }
}
} // namespace msime::windows

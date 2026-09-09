#include "InputQueue.h"

namespace msime::windows {
namespace {
thread_local const InputQueue *active_queue = nullptr;
struct WorkerScope {
  explicit WorkerScope(const InputQueue *queue) { active_queue = queue; }
  ~WorkerScope() { active_queue = nullptr; }
};
} // namespace
InputState::InputState(FocusGate &gate, size_t clients, std::string options)
    : gate_(gate), router_(gate, clients), options_(std::move(options)) {
  if (options_.empty() || options_.size() > 16384)
    throw std::invalid_argument("Invalid input queue configuration");
}
InputState::~InputState() { shutdown(); }
void InputState::shutdown() noexcept {
  // Sessions must release their thread-local Rust handles on this same worker.
  // Shutdown is fail-closed even if shared Engine cleanup reports an error.
  for (auto &[id, client] : clients_) {
    (void)id;
    try {
      cleanup(router_.disconnected(client.ticket));
    } catch (...) {
      gate_.invalidate(client.ticket);
    }
  }
  clients_.clear();
}
void InputState::check_thread() const {
  if (std::this_thread::get_id() != thread_)
    throw std::logic_error("Wrong input state thread");
}
FocusedSession *InputState::session(const PipeTicket &ticket) {
  auto found = clients_.find(ticket.client);
  return found != clients_.end() && same_ticket(found->second.ticket, ticket)
             ? found->second.session.get()
             : nullptr;
}
void InputState::cleanup(const FocusRoute &route) {
  if (route.cleanup)
    if (auto *owner = session(route.cleanup->transport))
      owner->cancel(*route.cleanup);
}
FocusRoute InputState::connected(const PipeTicket &ticket) {
  check_thread();
  auto result = router_.connected(ticket);
  if (!result.accepted)
    return result;
  cleanup(result);
  auto found = clients_.find(ticket.client);
  if (found != clients_.end())
    found->second.ticket = ticket;
  else {
    try {
      clients_.emplace(ticket.client,
                       Client{ticket, std::make_unique<FocusedSession>(
                                          gate_, ticket.client, options_)});
    } catch (...) {
      router_.disconnected(ticket);
      throw;
    }
  }
  return result;
}
FocusRoute InputState::disconnected(const PipeTicket &ticket) {
  check_thread();
  auto result = router_.disconnected(ticket);
  if (result.accepted) {
    cleanup(result);
    clients_.erase(ticket.client);
  }
  return result;
}
FocusRoute InputState::dispatch(const PipeTicket &ticket,
                                const FanyImeNamedpipeData &packet) {
  check_thread();
  auto result = router_.dispatch(ticket, packet);
  cleanup(result);
  if (result.activation) {
    auto *owner = session(ticket);
    if (!owner || !owner->prepare(result.activation->pending)) {
      cleanup(router_.failed(result.activation->pending));
      return {};
    }
  }
  return result;
}
bool InputState::confirmed(const FocusLease &lease) {
  check_thread();
  if (!router_.confirmed(lease))
    return false;
  if (preferences_) {
    auto *owner = session(lease.transport);
    return owner && owner->queue_preferences(lease, preferences_->serialized());
  }
  return true;
}
FocusRoute InputState::failed(const FocusLease &lease) {
  check_thread();
  auto result = router_.failed(lease);
  cleanup(result);
  return result;
}
std::optional<PendingReply>
InputState::key(const FocusLease &lease, const FanyImeNamedpipeData &packet,
                ReplyPath path, bool uiless,
                std::optional<std::string> local_text) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->key(lease, packet, path, uiless, std::move(local_text))
               : std::nullopt;
}
std::optional<PendingReply>
InputState::navigate(const FocusLease &lease,
                     const FanyImeNamedpipeData &packet,
                     const NavigationBindings &bindings) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->navigate(lease, packet, bindings) : std::nullopt;
}
std::optional<PendingReply> InputState::edit(const FocusLease &lease,
                                             const FanyImeNamedpipeData &packet,
                                             TsfPreeditStyle style) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->edit(lease, packet, style) : std::nullopt;
}
std::optional<PendingReply>
InputState::basic_key(const FocusLease &lease,
                      const FanyImeNamedpipeData &packet, TsfPreeditStyle style,
                      std::optional<std::string> local_text) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->basic_key(lease, packet, style, std::move(local_text))
               : std::nullopt;
}
bool InputState::synchronize_input_mode(const FocusLease &lease,
                                        const FanyImeNamedpipeData &packet) {
  check_thread();
  if (!valid_main_frame(packet, lease.transport.client) ||
      (packet.event_type != FanyImePipeEventType::IMESwitch &&
       packet.event_type != FanyImePipeEventType::PuncSwitch &&
       packet.event_type != FanyImePipeEventType::StatusSnapshot &&
       packet.event_type != FanyImePipeEventType::FocusRestored))
    throw std::invalid_argument("Invalid input mode notification");
  auto *owner = session(lease.transport);
  if (!owner)
    return false;
  if (packet.event_type == FanyImePipeEventType::PuncSwitch)
    return owner->set_chinese_punctuation(lease, packet.keycode != 0);
  if (!owner->set_input_enabled(lease, packet.keycode != 0))
    return false;
  if (packet.event_type == FanyImePipeEventType::StatusSnapshot ||
      packet.event_type == FanyImePipeEventType::FocusRestored)
    return owner->set_chinese_punctuation(lease, packet.pinyin_length != 0);
  return true;
}
bool InputState::delivered(const FocusLease &lease, uint64_t request) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner && owner->confirm(lease, request);
}
std::optional<nlohmann::json>
InputState::update_preferences(const FocusLease &lease,
                               const std::string &snapshot) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->update_preferences(lease, snapshot) : std::nullopt;
}
void InputState::publish_preferences(const PreferenceSnapshot &snapshot) {
  check_thread();
  if (preferences_ && (snapshot.revision() < preferences_->revision() ||
                       (snapshot.revision() == preferences_->revision() &&
                        snapshot.serialized() != preferences_->serialized())))
    throw std::invalid_argument("Stale or conflicting published preferences");
  preferences_ = snapshot;
  for (auto &[id, client] : clients_) {
    (void)id;
    client.session->queue_current_preferences(snapshot.serialized());
  }
}
bool InputState::queue_preferences(const FocusLease &lease,
                                   const std::string &snapshot) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner && owner->queue_preferences(lease, snapshot);
}

InputQueue::InputQueue(FocusGate &gate, size_t clients, size_t capacity,
                       std::string options)
    : capacity_(capacity) {
  if (!capacity || capacity > 4096)
    throw std::invalid_argument("Invalid input queue capacity");
  worker_ = std::thread(&InputQueue::run, this, std::ref(gate), clients,
                        std::move(options));
  std::unique_lock lock(mutex_);
  ready_.wait(lock, [&] { return started_; });
  if (startup_failed_) {
    lock.unlock();
    worker_.join();
    throw std::runtime_error("Input queue initialization failed");
  }
}
InputQueue::~InputQueue() { stop(); }
std::optional<std::future<InputTaskStatus>> InputQueue::submit(Task task) {
  if (!task)
    return std::nullopt;
  Job job{std::move(task), {}};
  auto completion = job.completion.get_future();
  {
    std::lock_guard lock(mutex_);
    if (stopping_ || jobs_.size() >= capacity_)
      return std::nullopt;
    jobs_.push_back(std::move(job));
  }
  ready_.notify_one();
  return completion;
}
void InputQueue::request_stop() {
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
    stats_.accepting = false;
  }
  ready_.notify_one();
}
void InputQueue::stop() {
  // Test before the join lock: a task must not deadlock with external stop().
  if (active_queue == this)
    throw std::logic_error("Input worker cannot join itself");
  std::lock_guard lock(stop_mutex_);
  request_stop();
  if (worker_.joinable())
    worker_.join();
}
InputQueueStats InputQueue::stats() const {
  std::lock_guard lock(mutex_);
  auto result = stats_;
  result.queued = jobs_.size();
  return result;
}
bool InputQueue::on_worker_thread() const noexcept { return active_queue == this; }
void InputQueue::run(FocusGate &gate, size_t clients, std::string options) {
  WorkerScope scope(this);
  try {
    InputState state(gate, clients, std::move(options));
    {
      std::lock_guard lock(mutex_);
      stats_.accepting = true;
      started_ = true;
    }
    ready_.notify_all();
    for (;;) {
      Job job;
      std::deque<Job> cancelled;
      {
        std::unique_lock lock(mutex_);
        ready_.wait(lock, [&] { return stopping_ || !jobs_.empty(); });
        if (stopping_) {
          cancelled.swap(jobs_);
          stats_.cancelled += cancelled.size();
        } else {
          job = std::move(jobs_.front());
          jobs_.pop_front();
          stats_.active = true;
        }
      }
      if (!job.task) {
        for (auto &pending : cancelled)
          pending.completion.set_value(InputTaskStatus::Cancelled);
        break;
      }
      auto status = InputTaskStatus::Completed;
      try {
        job.task(state);
      } catch (...) {
        // No raw exception text/input escapes the queue. Stop before any later
        // task can act on partially advanced Engine or routing state.
        status = InputTaskStatus::Failed;
        state.shutdown();
        request_stop();
      }
      {
        std::lock_guard lock(mutex_);
        stats_.active = false;
        if (status == InputTaskStatus::Completed)
          ++stats_.completed;
        else
          ++stats_.failed;
      }
      job.completion.set_value(status);
    }
  } catch (...) {
    std::deque<Job> cancelled;
    {
      std::lock_guard lock(mutex_);
      startup_failed_ = !started_;
      started_ = true;
      stopping_ = true;
      stats_.accepting = false;
      stats_.active = false;
      cancelled.swap(jobs_);
      stats_.cancelled += cancelled.size();
    }
    for (auto &pending : cancelled)
      pending.completion.set_value(InputTaskStatus::Cancelled);
    ready_.notify_all();
  }
}
std::optional<PendingReply> InputState::configured_key(
    const FocusLease &lease, const FanyImeNamedpipeData &packet,
    TsfPreeditStyle style, const NavigationBindings &bindings,
    std::optional<std::string> local_text) {
  check_thread();
  auto *owner = session(lease.transport);
  return owner ? owner->configured_key(lease, packet, style, bindings,
                                       std::move(local_text))
               : std::nullopt;
}
} // namespace msime::windows

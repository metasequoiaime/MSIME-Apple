#include "PreferenceMonitor.h"
#include <filesystem>

namespace msime::windows {
PreferenceMonitor::PreferenceMonitor(InputQueue &input, std::string directory,
                                     std::chrono::milliseconds interval)
    : input_(input), directory_(std::move(directory)), interval_(interval) {
  if (directory_.empty() || directory_.size() > 16384 ||
      !std::filesystem::u8path(directory_).is_absolute() ||
      interval_ < std::chrono::milliseconds(10) ||
      interval_ > std::chrono::minutes(1))
    throw std::invalid_argument("Invalid preference monitor configuration");
  worker_ = std::thread([this] { run(); });
}
PreferenceMonitor::~PreferenceMonitor() { stop(); }
void PreferenceMonitor::request_stop() {
  {
    std::lock_guard lock(mutex_);
    stopping_ = true;
  }
  wake_.notify_all();
}
void PreferenceMonitor::stop() {
  if (input_.on_worker_thread())
    throw std::logic_error("Cannot join preference monitor from input queue");
  std::lock_guard join(join_mutex_);
  if (worker_.joinable() && worker_.get_id() == std::this_thread::get_id())
    throw std::logic_error("Cannot join preference monitor from itself");
  request_stop();
  if (worker_.joinable())
    worker_.join();
}
void PreferenceMonitor::run() {
  std::optional<PreferenceSnapshot> published, pending;
  std::optional<std::future<InputTaskStatus>> receipt;
  for (;;) {
    {
      std::lock_guard lock(mutex_);
      if (stopping_)
        break;
    }
    if (!input_.stats().accepting) {
      status_ = PreferenceMonitorStatus::InputUnavailable;
      return;
    }
    try {
      if (receipt && receipt->wait_for(std::chrono::milliseconds(0)) ==
                         std::future_status::ready) {
        if (receipt->get() != InputTaskStatus::Completed) {
          status_ = PreferenceMonitorStatus::PublicationFailed;
          return;
        }
        receipt.reset();
        published = std::move(pending);
        pending.reset();
        status_ = PreferenceMonitorStatus::Current;
      }
      if (!receipt) {
        auto snapshot = PreferenceSnapshot::try_load(directory_);
        if (!snapshot)
          status_ = PreferenceMonitorStatus::Busy;
        else if (published &&
                 (snapshot->revision() < published->revision() ||
                  (snapshot->revision() == published->revision() &&
                   snapshot->serialized() != published->serialized())))
          status_ = PreferenceMonitorStatus::ReadFailed;
        else if (published && snapshot->serialized() == published->serialized())
          status_ = PreferenceMonitorStatus::Current;
        else {
          {
            std::lock_guard lock(mutex_);
            if (stopping_)
              break;
          }
          receipt = input_.submit([value = *snapshot](InputState &state) {
            state.publish_preferences(value);
          });
          if (receipt) {
            pending = std::move(snapshot);
            status_ = PreferenceMonitorStatus::Publishing;
          } else
            status_ = PreferenceMonitorStatus::QueueFull;
        }
      }
    } catch (...) {
      if (receipt) {
        status_ = PreferenceMonitorStatus::PublicationFailed;
        return;
      }
      // A read failure preserves the last publication. No paths/raw errors.
      status_ = PreferenceMonitorStatus::ReadFailed;
    }
    std::unique_lock lock(mutex_);
    if (wake_.wait_for(lock, interval_, [&] { return stopping_; }))
      break;
  }
  status_ = PreferenceMonitorStatus::Stopped;
}
} // namespace msime::windows

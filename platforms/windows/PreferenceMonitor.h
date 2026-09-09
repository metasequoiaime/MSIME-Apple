#pragma once
#include "InputQueue.h"
#include <atomic>
#include <chrono>

namespace msime::windows {
enum class PreferenceMonitorStatus {
  Starting,
  Current,
  Busy,
  ReadFailed,
  QueueFull,
  Publishing,
  Stopped,
  InputUnavailable,
  PublicationFailed
};
// One settings worker, at most one outstanding input task. InputQueue outlives
// stop(). Disk I/O can still block; no file lock wait or detached thread.
class PreferenceMonitor final {
public:
  PreferenceMonitor(
      InputQueue &input, std::string directory,
      std::chrono::milliseconds interval = std::chrono::milliseconds(250));
  ~PreferenceMonitor();
  PreferenceMonitor(const PreferenceMonitor &) = delete;
  PreferenceMonitor &operator=(const PreferenceMonitor &) = delete;
  void request_stop();
  void stop(); // External owner only; never from an input task.
  PreferenceMonitorStatus status() const { return status_.load(); }
  bool failed() const {
    const auto value = status();
    return value == PreferenceMonitorStatus::InputUnavailable ||
           value == PreferenceMonitorStatus::PublicationFailed;
  }

private:
  void run();
  InputQueue &input_;
  std::string directory_;
  std::chrono::milliseconds interval_;
  std::atomic<PreferenceMonitorStatus> status_{
      PreferenceMonitorStatus::Starting};
  std::mutex mutex_, join_mutex_;
  std::condition_variable wake_;
  bool stopping_ = false;
  std::thread worker_;
};
} // namespace msime::windows

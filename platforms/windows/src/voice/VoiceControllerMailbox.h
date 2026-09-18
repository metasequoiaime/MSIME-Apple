#pragma once
#include "VoiceControllerDispatch.h"
#include <chrono>
#include <condition_variable>

namespace msime::windows {
struct VoiceControllerJob {
  std::shared_ptr<VoiceControllerChannel> channel;
  VoiceControllerRequest request;
  void complete(VoiceControllerResponse response) {
    std::lock_guard lock(mutex_);
    if (!channel->alive.load() || response_)
      return;
    response_ = std::move(response);
    ready_.notify_one();
  }
  std::optional<VoiceControllerResponse> wait(std::chrono::milliseconds slice) {
    std::unique_lock lock(mutex_);
    ready_.wait_for(lock, slice, [&] { return response_.has_value(); });
    return std::move(response_);
  }

private:
  std::mutex mutex_;
  std::condition_variable ready_;
  std::optional<VoiceControllerResponse> response_;
};
// Single outstanding request across this endpoint. Taking a job releases the
// queue lock before any backend action. Disconnected queued work is inert.
class VoiceControllerMailbox final {
public:
  bool publish(const std::shared_ptr<VoiceControllerJob> &job) {
    std::lock_guard lock(mutex_);
    if (pending_ && !pending_->channel->alive.load())
      pending_.reset();
    if (pending_ || !job || !job->channel || !job->channel->alive.load())
      return false;
    pending_ = job;
    return true;
  }
  std::shared_ptr<VoiceControllerJob> take() {
    std::lock_guard lock(mutex_);
    return std::exchange(pending_, {});
  }

private:
  std::mutex mutex_;
  std::shared_ptr<VoiceControllerJob> pending_;
};
} // namespace msime::windows

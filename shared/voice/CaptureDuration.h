#pragma once
#include <cmath>
#include <cstdint>
#include <mutex>

namespace msime::voice {
// MSIME-Windows develop 30a22e6f discards captures shorter than 1/4 second.
// Count admitted input frames, not wall time or resampler padding.
inline bool short_capture(double seconds) {
  return !std::isfinite(seconds) || seconds < 0.25;
}
class CaptureDuration {
public:
  explicit CaptureDuration(double sample_rate) : sample_rate_(sample_rate) {}
  bool append(std::uint64_t frames) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_) return false;
    frames_ += frames;
    return true;
  }
  double seconds() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return duration();
  }
  double finish() {
    std::lock_guard<std::mutex> lock(mutex_);
    stopped_ = true;
    return duration();
  }
private:
  double duration() const {
    return std::isfinite(sample_rate_) && sample_rate_ > 0 ? frames_ / sample_rate_ : 0;
  }
  const double sample_rate_;
  mutable std::mutex mutex_;
  std::uint64_t frames_ = 0;
  bool stopped_ = false;
};
} // namespace msime::voice

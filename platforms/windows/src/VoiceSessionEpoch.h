#pragma once
#include <atomic>
#include <cstdint>
#include <mutex>

namespace msime::windows {
// Serializes generation changes with externally visible completion effects.
// Callbacks must not re-enter this gate or wait for capture/network workers.
class VoiceSessionEpoch final {
public:
  uint64_t load() const { return value_.load(); }
  uint64_t fetch_add(uint64_t amount) {
    std::lock_guard lock(mutex_);
    return value_.fetch_add(amount);
  }
  template <typename Effect>
  bool with_current(uint64_t expected, Effect effect) {
    std::lock_guard lock(mutex_);
    if (value_.load() != expected)
      return false;
    effect();
    return true;
  }

private:
  std::atomic<uint64_t> value_{0};
  std::mutex mutex_;
};
} // namespace msime::windows

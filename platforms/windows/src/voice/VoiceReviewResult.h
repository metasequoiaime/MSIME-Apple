#pragma once
#include "VoiceControllerProtocol.h"
#include <algorithm>
#include <cmath>
#include <memory>
#include <mutex>

namespace msime::windows {
// One object per capture. Workers retain that object, never a mutable pointer
// to the next session. Polling copies a bounded snapshot; no callbacks run
// here.
class VoiceReviewResult final {
public:
  using Phase = FanyImeVoiceController::Phase;
  struct Snapshot {
    Phase phase = Phase::Recording;
    uint32_t level = 0;
    std::string text;
  };
  Snapshot snapshot() const {
    std::lock_guard lock(mutex_);
    return value_;
  }
  bool active() const {
    std::lock_guard lock(mutex_);
    return active_locked();
  }
  void level(float value) {
    std::lock_guard lock(mutex_);
    if (value_.phase == Phase::Recording)
      value_.level =
          std::isfinite(value)
              ? static_cast<uint32_t>(std::clamp(value, 0.0f, 1.0f) *
                                      FanyImeVoiceController::MaxLevel)
              : 0;
  }
  void recognizing() {
    std::lock_guard lock(mutex_);
    if (value_.phase == Phase::Recording) {
      value_.phase = Phase::Recognizing;
      value_.level = 0;
    }
  }
  void processing() {
    std::lock_guard lock(mutex_);
    if (value_.phase == Phase::Recognizing)
      value_.phase = Phase::Processing;
  }
  void complete(std::string_view text) {
    std::lock_guard lock(mutex_);
    if (value_.phase != Phase::Recognizing && value_.phase != Phase::Processing)
      return;
    if (text.empty() || text.size() > FanyImeVoiceController::MaxTextBytes ||
        !controller_utf8(text)) {
      value_ = {Phase::Failed, 0, {}};
      return;
    }
    value_ = {Phase::Complete, 0, std::string(text)};
  }
  void fail() {
    std::lock_guard lock(mutex_);
    if (active_locked())
      value_ = {Phase::Failed, 0, {}};
  }
  // Cancellation also retires a completed, not-yet-consumed result.
  void cancel() {
    std::lock_guard lock(mutex_);
    value_ = {Phase::Cancelled, 0, {}};
  }

private:
  bool active_locked() const {
    return value_.phase == Phase::Recording ||
           value_.phase == Phase::Recognizing ||
           value_.phase == Phase::Processing;
  }
  mutable std::mutex mutex_;
  Snapshot value_;
};

// `streaming`: the recognizer reports partial text while recording (Doubao, or an installed on-device model).
inline bool
voice_inline_allowed(const std::shared_ptr<VoiceReviewResult> &review,
                     bool enabled, bool streaming, std::string_view mode) {
  return !review && enabled && streaming && mode == "tsf";
}

// The native callback contains ALL automatic commit routes, including fallback.
// Review results never execute it, even when their transcript is invalid.
template <typename NativeCommit>
void deliver_voice_result(const std::shared_ptr<VoiceReviewResult> &review,
                          std::string_view text, NativeCommit native_commit) {
  if (review)
    review->complete(text);
  else
    native_commit();
}
} // namespace msime::windows

#pragma once
#include <chrono>
#include <optional>

namespace msime::windows {
// The HideCandidateWnd the TIP sends when a Wubi auto-commit ends its composition must not clear the composition the Server continues with (the letter that triggered a top-commit). A delivered continuation arms this mark and the next hide consumes it, but only within a second, the reference's limit: a continuation the TIP dropped (focus or composition epoch changed) never produces that hide, and a stale mark must not later spare a composition the user really closed.
class ContinuationHide {
public:
  using Clock = std::chrono::steady_clock;
  static constexpr std::chrono::milliseconds lifetime{1000};
  void arm(Clock::time_point now) { armed_at_ = now; }
  void clear() { armed_at_.reset(); }
  // True when the mark was armed no more than `lifetime` ago. Either way the mark is spent: one continuation answers for one hide.
  bool consume(Clock::time_point now) {
    const auto armed_at = armed_at_;
    armed_at_.reset();
    return armed_at && now >= *armed_at && now - *armed_at <= lifetime;
  }

private:
  std::optional<Clock::time_point> armed_at_;
};
} // namespace msime::windows

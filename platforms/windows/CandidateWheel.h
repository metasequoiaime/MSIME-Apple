#pragma once

namespace msime::windows {
struct CandidateWheelSteps {
  int page_up = 0;
  int page_down = 0;
};

// Fold high-precision wheel deltas into whole WHEEL_DELTA notches. A direction
// reversal drops the old partial notch so the first notch in the new direction
// is not delayed by stale travel.
constexpr CandidateWheelSteps consume_candidate_wheel_delta(int &accumulator,
                                                            int delta,
                                                            int notch) {
  CandidateWheelSteps steps;
  if (notch <= 0)
    return steps;
  if ((accumulator > 0 && delta < 0) || (accumulator < 0 && delta > 0))
    accumulator = 0;
  accumulator += delta;
  while (accumulator >= notch) {
    accumulator -= notch;
    ++steps.page_up;
  }
  while (accumulator <= -notch) {
    accumulator += notch;
    ++steps.page_down;
  }
  return steps;
}
} // namespace msime::windows

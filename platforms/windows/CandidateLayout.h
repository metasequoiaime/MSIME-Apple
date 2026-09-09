#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <stdexcept>

namespace msime::windows {
struct CandidateMetrics {
  int width, row, padding, font;
};
inline CandidateMetrics candidate_metrics(unsigned dpi) {
  if (dpi < 48 || dpi > 960)
    throw std::invalid_argument("Invalid candidate DPI");
  auto scale = [dpi](unsigned value) {
    return static_cast<int>((value * dpi + 48) / 96);
  };
  return {scale(420), scale(28), scale(4), scale(16)};
}
struct CandidateBounds {
  int x, y, width, height;
};
// Screen pixels, including negative monitor origins. Widen before subtracting
// so untrusted caret coordinates cannot overflow placement arithmetic.
inline CandidateBounds candidate_bounds(int x, int y, int left, int top,
                                        int right, int bottom, unsigned dpi,
                                        size_t candidates) {
  const auto metrics = candidate_metrics(dpi);
  const int64_t available_width = int64_t(right) - left;
  const int64_t available_height = int64_t(bottom) - top;
  if (candidates > 9 || available_width <= 0 || available_height <= 0)
    throw std::invalid_argument("Invalid candidate layout");
  const auto width = (std::min)(int64_t(metrics.width), available_width);
  const auto height =
      (std::min)(int64_t((candidates + 1) * metrics.row + 2 * metrics.padding),
                 available_height);
  return {static_cast<int>(
              (std::clamp)(int64_t(x), int64_t(left), int64_t(right) - width)),
          static_cast<int>(
              (std::clamp)(int64_t(y), int64_t(top), int64_t(bottom) - height)),
          static_cast<int>(width), static_cast<int>(height)};
}
} // namespace msime::windows

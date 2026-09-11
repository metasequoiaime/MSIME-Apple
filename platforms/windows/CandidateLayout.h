#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <stdexcept>

namespace msime::windows {
struct CandidateMetrics {
  int width, row, padding, font;
};
inline CandidateMetrics candidate_metrics(unsigned dpi, unsigned font_size = 16) {
  if (dpi < 48 || dpi > 960)
    throw std::invalid_argument("Invalid candidate DPI");
  if (font_size < 12 || font_size > 32)
    throw std::invalid_argument("Invalid candidate font size");
  auto scale = [dpi](unsigned value) {
    return static_cast<int>((value * dpi + 48) / 96);
  };
  auto size = [font_size](unsigned value) { return (value * font_size + 8) / 16; };
  return {scale(size(420)), scale(size(28)), scale(size(4)), scale(font_size)};
}
struct CandidateBounds {
  int x, y, width, height;
};
inline std::optional<size_t> candidate_hit(int x, int y, int width, int height,
                                           unsigned dpi, size_t count,
                                           unsigned font_size = 16,
                                           bool horizontal = false) {
  const auto metrics = candidate_metrics(dpi, font_size);
  if (count == 0 || count > 9 || x < metrics.padding ||
      int64_t(x) >= int64_t(width) - metrics.padding ||
      y < metrics.padding + metrics.row || y >= height)
    return std::nullopt;
  if (horizontal) {
    const auto inner_width = (width - 2 * metrics.padding);
    const auto column_width = (inner_width + static_cast<int>(count) - 1) /
                              static_cast<int>(count);
    const auto column = static_cast<size_t>((x - metrics.padding) / column_width);
    return y >= metrics.padding + metrics.row && y < metrics.padding + 2 * metrics.row && column < count
      ? std::optional<size_t>(column) : std::nullopt;
  }
  const auto row = static_cast<size_t>((y - metrics.padding) / metrics.row - 1);
  return row < count ? std::optional<size_t>(row) : std::nullopt;
}
// Screen pixels, including negative monitor origins. Widen before subtracting
// so untrusted caret coordinates cannot overflow placement arithmetic.
inline CandidateBounds candidate_bounds(int x, int y, int left, int top,
                                        int right, int bottom, unsigned dpi,
                                        size_t candidates,
                                        unsigned font_size = 16,
                                        bool horizontal = false) {
  const auto metrics = candidate_metrics(dpi, font_size);
  const int64_t available_width = int64_t(right) - left;
  const int64_t available_height = int64_t(bottom) - top;
  if (candidates > 9 || available_width <= 0 || available_height <= 0)
    throw std::invalid_argument("Invalid candidate layout");
  const auto width = (std::min)(int64_t(horizontal ? metrics.width : metrics.width), available_width);
  const auto height =
      (std::min)(int64_t((horizontal ? 2 : (candidates + 1)) * metrics.row + 2 * metrics.padding),
                 available_height);
  return {static_cast<int>(
              (std::clamp)(int64_t(x), int64_t(left), int64_t(right) - width)),
          static_cast<int>(
              (std::clamp)(int64_t(y), int64_t(top), int64_t(bottom) - height)),
          static_cast<int>(width), static_cast<int>(height)};
}
} // namespace msime::windows

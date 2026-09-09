#pragma once
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <stdexcept>

namespace msime::windows {
struct ModeLayout {
  int x, y, cell_width, cell_height;
  int width() const { return cell_width * 2; }
  int height() const { return cell_height * 3; }
  std::optional<size_t> hit(int px, int py) const {
    if (px < 0 || py < 0 || px >= width() || py >= height())
      return {};
    return static_cast<size_t>(py / cell_height * 2 + px / cell_width);
  }
};
inline std::optional<ModeLayout> mode_layout(int left, int top, int right,
                                             int bottom, unsigned dpi) {
  if (dpi < 48 || dpi > 960 || right <= left || bottom <= top)
    throw std::invalid_argument("Invalid mode work area");
  const int64_t available_width = int64_t(right) - left;
  const int64_t available_height = int64_t(bottom) - top;
  if (available_width < 2 || available_height < 3)
    return {}; // Cannot allocate even one pixel per command.
  const int width = static_cast<int>(
      std::min<int64_t>((112 * dpi + 48) / 96, available_width / 2));
  const int height = static_cast<int>(
      std::min<int64_t>((34 * dpi + 48) / 96, available_height / 3));
  return ModeLayout{right - width * 2, bottom - height * 3, width, height};
}
} // namespace msime::windows

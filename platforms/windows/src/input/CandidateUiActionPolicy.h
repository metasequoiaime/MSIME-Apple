#pragma once

#include <cstddef>

namespace msime::windows {
// The Windows UI protocol exposes candidates as 1..10. The shared Engine
// uses zero-based indices, so keep the conversion boundary explicit here.
inline constexpr size_t candidate_ui_max_count = 10;

constexpr bool valid_candidate_ui_index(size_t index) noexcept {
  return index < candidate_ui_max_count;
}
} // namespace msime::windows

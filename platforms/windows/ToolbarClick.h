#pragma once
#include <cstddef>
#include <optional>
#include <utility>

namespace msime::windows {
// Consume once even when release misses or the active focus lease changed.
inline bool toolbar_release(std::optional<size_t> &pressed,
                            std::optional<size_t> released, bool same_context) {
  const auto down = std::exchange(pressed, std::nullopt);
  return same_context && down && released && down == released;
}
} // namespace msime::windows

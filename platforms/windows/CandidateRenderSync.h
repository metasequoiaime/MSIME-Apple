#pragma once

#include <cstdint>

namespace msime::windows {

// A keyboard selection may race the asynchronous candidate-window paint.  A
// rendered generation of zero means that no usable on-screen list exists.
// UI-less and hidden candidates deliberately skip the wait: there is no
// screen snapshot whose ordering can be used for those paths.
inline constexpr unsigned candidate_render_wait_max_ms = 30;

inline constexpr bool should_wait_for_candidate_render(
    std::uint64_t rendered_generation, std::uint64_t current_generation,
    bool ui_less, bool visible) noexcept {
  if (ui_less || !visible || rendered_generation == 0 ||
      current_generation == 0)
    return false;
  return rendered_generation < current_generation;
}

} // namespace msime::windows

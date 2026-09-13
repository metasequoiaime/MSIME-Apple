#pragma once
#include <algorithm>

namespace msime::windows {
// Where the floating toolbar goes. Physical pixels throughout.
//
// The corner is a starting position, not a rule. Recomputing it on every state
// change is what makes a toolbar the user dragged somewhere snap back to the
// bottom right the next time they switch between Chinese and English, which is
// often enough to make dragging pointless.
struct FloatingToolbarPlacementInput {
  int width = 0;
  int height = 0;
  int margin = 0;
  int work_left = 0, work_top = 0, work_right = 0, work_bottom = 0;
  // The window's current top-left, meaningful only once it has been placed.
  int current_x = 0, current_y = 0;
  // False until the toolbar has been positioned once this run.
  bool placed = false;
};
struct FloatingToolbarPlacement {
  int x = 0;
  int y = 0;
};
inline FloatingToolbarPlacement
floating_toolbar_placement(const FloatingToolbarPlacementInput &input) {
  int x = input.work_right - input.width - input.margin;
  int y = input.work_bottom - input.height - input.margin;
  if (input.placed) {
    x = input.current_x;
    y = input.current_y;
  }
  // Keep it wholly on screen either way. A work area smaller than the toolbar
  // would invert the range, so the lower bound wins and the toolbar stays at
  // the top left rather than being pushed off the opposite edge.
  const int max_x = (std::max)(input.work_left, input.work_right - input.width);
  const int max_y = (std::max)(input.work_top, input.work_bottom - input.height);
  x = (std::clamp)(x, input.work_left, max_x);
  y = (std::clamp)(y, input.work_top, max_y);
  return {x, y};
}
} // namespace msime::windows

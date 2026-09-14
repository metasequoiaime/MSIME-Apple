#include "FloatingToolbarPlacement.h"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("Floating toolbar placement failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
} // namespace
int main() {
  try {
    FloatingToolbarPlacementInput input;
    input.work_left = 0;
    input.work_top = 0;
    input.work_right = 1920;
    input.work_bottom = 1040;
    input.width = 400;
    input.height = 52;
    input.margin = 20;

    // First placement goes to the bottom-right corner, inset by the margin.
    const auto first = floating_toolbar_placement(input);
    require(first.x == 1920 - 400 - 20);
    require(first.y == 1040 - 52 - 20);

    // Once placed, the user's position is kept. This is the whole defect: the
    // toolbar used to jump back to the corner on the next mode change.
    input.placed = true;
    input.current_x = 300;
    input.current_y = 200;
    const auto dragged = floating_toolbar_placement(input);
    require(dragged.x == 300 && dragged.y == 200);
    require(dragged.x != first.x || dragged.y != first.y);

    // A position dragged partly off an edge is pulled back wholly on screen,
    // without being sent to the corner.
    input.current_x = 1900;
    input.current_y = 1030;
    const auto reclamped = floating_toolbar_placement(input);
    require(reclamped.x == 1920 - 400);
    require(reclamped.y == 1040 - 52);
    input.current_x = -200;
    input.current_y = -50;
    const auto pulled = floating_toolbar_placement(input);
    require(pulled.x == 0 && pulled.y == 0);

    // Offsets follow the work area, so a non-zero origin (taskbar on the left
    // or top, or a secondary monitor) is respected rather than assumed to be 0.
    FloatingToolbarPlacementInput offset = input;
    offset.work_left = 2000;
    offset.work_top = 100;
    offset.work_right = 3920;
    offset.work_bottom = 1140;
    offset.placed = false;
    const auto second_screen = floating_toolbar_placement(offset);
    require(second_screen.x == 3920 - 400 - 20);
    require(second_screen.y == 1140 - 52 - 20);
    offset.placed = true;
    offset.current_x = 2500;
    offset.current_y = 300;
    require(floating_toolbar_placement(offset).x == 2500);
    // Clamping uses that origin too, not 0.
    offset.current_x = 0;
    offset.current_y = 0;
    const auto clamped = floating_toolbar_placement(offset);
    require(clamped.x == 2000 && clamped.y == 100);

    // A work area narrower than the toolbar must not push it off the left edge
    // by inverting the clamp range; the origin wins.
    FloatingToolbarPlacementInput tiny;
    tiny.work_left = 0;
    tiny.work_top = 0;
    tiny.work_right = 100;
    tiny.work_bottom = 30;
    tiny.width = 400;
    tiny.height = 52;
    tiny.margin = 20;
    const auto squeezed = floating_toolbar_placement(tiny);
    require(squeezed.x == 0 && squeezed.y == 0);
    tiny.placed = true;
    tiny.current_x = 50;
    tiny.current_y = 10;
    const auto squeezed_drag = floating_toolbar_placement(tiny);
    require(squeezed_drag.x == 0 && squeezed_drag.y == 0);

    std::cout << "Floating toolbar placement: the dragged position survives\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Floating toolbar placement failed with an unknown error\n";
    return 1;
  }
}

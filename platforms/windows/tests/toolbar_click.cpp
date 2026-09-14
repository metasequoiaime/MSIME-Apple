#include "../ToolbarClick.h"
#include <cassert>
using namespace msime::windows;
int main() {
  std::optional<size_t> pressed;
  assert(!toolbar_release(pressed, 0, true));
  for (size_t button = 0; button < 11; ++button) {
    pressed = button;
    assert(toolbar_release(pressed, button, true));
    assert(!pressed);
    assert(!toolbar_release(pressed, button, true));
    pressed = button;
    assert(!toolbar_release(pressed, (button + 1) % 11, true));
    assert(!pressed);
    pressed = button;
    assert(!toolbar_release(pressed, std::nullopt, true));
    assert(!pressed);
    pressed = button;
    assert(!toolbar_release(pressed, button, false));
    assert(!pressed);
    // Hide, layout/DPI changes, leave and cancellation all reset the press.
    pressed = button;
    pressed.reset();
    assert(!toolbar_release(pressed, button, true));
  }
}

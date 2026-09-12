#include "FloatingToolbarVisibilityPolicy.h"

#include <cassert>

int main() {
  using msime::windows::ShouldDeferFloatingToolbarHide;
  using msime::windows::ShouldShowFloatingToolbar;

  assert(ShouldShowFloatingToolbar(true, false, true));
  assert(!ShouldShowFloatingToolbar(false, false, true));
  assert(!ShouldShowFloatingToolbar(true, true, true));
  assert(!ShouldShowFloatingToolbar(true, false, false));
  assert(ShouldDeferFloatingToolbarHide(true));
  assert(!ShouldDeferFloatingToolbarHide(false));
}

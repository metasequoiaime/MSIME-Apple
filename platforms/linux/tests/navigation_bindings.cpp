#include "NavigationBindings.h"

#include <cassert>

int main() {
  msime::linux_host::NavigationBindings bindings;
  assert(bindings.command(msime::linux_host::kTouchKeyboardNextPage, false) ==
         MSIME_NEXT_PAGE);
  assert(bindings.command(msime::linux_host::kTouchKeyboardPreviousPage, false) ==
         MSIME_PREVIOUS_PAGE);

  bindings.tab = false;
  bindings.page_up_down = false;
  bindings.brackets = false;
  assert(bindings.command(msime::linux_host::kTouchKeyboardNextPage, true) ==
         MSIME_NEXT_PAGE);
  assert(bindings.command(msime::linux_host::kTouchKeyboardPreviousPage, true) ==
         MSIME_PREVIOUS_PAGE);
  return 0;
}

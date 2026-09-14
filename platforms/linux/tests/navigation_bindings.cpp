#include "NavigationBindings.h"
#include "WordCharacterBinding.h"

#include <cassert>

int main() {
  auto word_character =
      msime::linux_host::WordCharacterBinding::read(nlohmann::json::object());
  assert(word_character.enabled);
  assert(word_character.edge(IBUS_bracketleft, false) == MSIME_FIRST_HAN);
  assert(word_character.edge(IBUS_bracketright, false) == MSIME_LAST_HAN);
  assert(!word_character.edge(IBUS_minus, false));

  msime::linux_host::NavigationBindings bindings;
  assert(bindings.command(msime::linux_host::kTouchKeyboardNextPage, false) ==
         MSIME_NEXT_PAGE);
  assert(bindings.command(msime::linux_host::kTouchKeyboardPreviousPage, false) ==
         MSIME_PREVIOUS_PAGE);

  bindings.tab = false;
  bindings.page_up_down = false;
  bindings.brackets = false;
  assert(!bindings.wheel_command(4));
  bindings.mouse_wheel = true;
  assert(bindings.wheel_command(4) == MSIME_PREVIOUS_PAGE);
  assert(bindings.wheel_command(5) == MSIME_NEXT_PAGE);
  assert(!bindings.wheel_command(1));
  assert(bindings.command(msime::linux_host::kTouchKeyboardNextPage, true) ==
         MSIME_NEXT_PAGE);
  assert(bindings.command(msime::linux_host::kTouchKeyboardPreviousPage, true) ==
         MSIME_PREVIOUS_PAGE);
  return 0;
}

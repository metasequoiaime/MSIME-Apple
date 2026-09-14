#include "HelpcodeDefaults.h"
#include "NavigationBindings.h"
#include "WordCharacterBinding.h"

#include <cassert>

int main() {
  assert(msime::linux_host::default_helpcode_schema("quanpin") == "ziranma");
  assert(!msime::linux_host::default_show_helpcode("quanpin"));
  assert(msime::linux_host::default_helpcode_schema("shuangpin") == "lantian");
  assert(msime::linux_host::default_show_helpcode("shuangpin"));

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

  const auto malformed_array = nlohmann::json{
      {"navigation", nlohmann::json::array({"invalid"})}};
  const auto fallback_array =
      msime::linux_host::NavigationBindings::read(malformed_array);
  assert(fallback_array.tab && fallback_array.page_up_down &&
         fallback_array.arrows && !fallback_array.mouse_wheel);
  const auto malformed_scalar =
      nlohmann::json{{"navigation", nlohmann::json("invalid")}};
  const auto fallback_scalar =
      msime::linux_host::NavigationBindings::read(malformed_scalar);
  assert(fallback_scalar.minus_equal && fallback_scalar.comma_period &&
         !fallback_scalar.brackets);
  return 0;
}

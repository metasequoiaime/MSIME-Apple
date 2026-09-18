#include "input/InputKeyPolicy.h"
#include <cassert>

int main() {
  using msime::windows::should_learn_entered_english_word;
  using msime::windows::normalize_numpad_digit_key;
  using msime::windows::is_backend_independent_reset_key;
  assert(normalize_numpad_digit_key(0x60) == '0');
  assert(normalize_numpad_digit_key(0x69) == '9');
  assert(normalize_numpad_digit_key(0x41) == 0x41);
  assert(is_backend_independent_reset_key(0x1B));
  assert(is_backend_independent_reset_key(0xA1));
  assert(!is_backend_independent_reset_key(0xA2));
  using msime::windows::should_send_composition_reply;
  assert(should_send_composition_reply(false, false, false, false, false,
                                        true));
  assert(!should_send_composition_reply(false, false, false, false, false,
                                         false));
  assert(should_learn_entered_english_word(false, false, true, false));
  assert(should_learn_entered_english_word(true, false, true, true));
  assert(should_learn_entered_english_word(false, true, true, true));
  assert(should_learn_entered_english_word(false, true, false, true));
  assert(!should_learn_entered_english_word(false, false, true, true));
  assert(!should_learn_entered_english_word(false, false, false, false));
}

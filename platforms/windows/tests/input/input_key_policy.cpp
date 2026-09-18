#include "input/InputKeyPolicy.h"
#include <cassert>

int main() {
  using msime::windows::should_learn_entered_english_word;
  assert(should_learn_entered_english_word(false, false, true, false));
  assert(should_learn_entered_english_word(true, false, true, true));
  assert(should_learn_entered_english_word(false, true, true, true));
  assert(should_learn_entered_english_word(false, true, false, true));
  assert(!should_learn_entered_english_word(false, false, true, true));
  assert(!should_learn_entered_english_word(false, false, false, false));
}

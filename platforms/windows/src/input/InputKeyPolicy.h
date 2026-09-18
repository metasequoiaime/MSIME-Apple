#pragma once

namespace msime::windows {

// Enter learns an ASCII word only for the same cases as the Windows server:
// dedicated English, a Shift-letter special mode, or an incomplete Chinese
// composition. Complete pure-pinyin input is deliberately excluded because
// it represents Chinese candidate input rather than an entered English word.
constexpr bool should_learn_entered_english_word(bool dedicated_english_mode,
                                                 bool shift_letter_special_mode,
                                                 bool chinese_scheme,
                                                 bool all_complete_pure_pinyin) {
  return dedicated_english_mode || shift_letter_special_mode ||
         (chinese_scheme && !all_complete_pure_pinyin);
}

} // namespace msime::windows

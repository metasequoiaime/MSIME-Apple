#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace msime::windows {

inline constexpr uint32_t kVirtualKeyBackspace = 0x08;
inline constexpr uint32_t kVirtualKeyLeft = 0x25;
inline constexpr uint32_t kVirtualKeyRight = 0x27;
inline constexpr uint32_t kModifierShift = 0b00000001u;
inline constexpr uint32_t kModifierControl = 0b00000010u;
inline constexpr uint32_t kModifierAlt = 0b00000100u;
inline constexpr uint32_t kKeyModifierMask = kModifierShift | kModifierControl | kModifierAlt;

constexpr bool is_segment_backspace_key(uint32_t keycode, uint32_t modifiers) {
  return keycode == kVirtualKeyBackspace &&
         (modifiers & kKeyModifierMask) == kModifierControl;
}

constexpr bool is_segment_caret_key(uint32_t keycode, uint32_t modifiers) {
  return (keycode == kVirtualKeyLeft || keycode == kVirtualKeyRight) &&
         (modifiers & kKeyModifierMask) == kModifierControl;
}

// A composing key needs a reverse-pipe reply when the TSF side cannot finish
// the edit locally. Japanese long-vowel input follows the same explicit policy
// as letters, separators, and Unicode digits.
constexpr bool should_send_composition_reply(bool is_alpha_key,
                                             bool is_manual_pinyin_separator,
                                             bool is_microsoft_shuangpin_ing_key,
                                             bool is_unicode_hex_digit,
                                             bool is_unicode_plus,
                                             bool is_japanese_long_vowel) {
  return is_alpha_key || is_manual_pinyin_separator ||
         is_microsoft_shuangpin_ing_key || is_unicode_hex_digit ||
         is_unicode_plus || is_japanese_long_vowel;
}

constexpr std::size_t previous_segment_boundary(const std::vector<std::size_t> &boundaries,
                                                std::size_t caret) {
  std::size_t result = caret;
  for (const auto boundary : boundaries) {
    if (boundary >= caret) break;
    result = boundary;
  }
  return result;
}

constexpr std::size_t next_segment_boundary(const std::vector<std::size_t> &boundaries,
                                            std::size_t caret) {
  for (const auto boundary : boundaries)
    if (boundary > caret) return boundary;
  return caret;
}

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

#pragma once

#include <cstdint>
#include <string>

namespace msime::input {

// English mode never reaches Engine's punctuation policy, because the session is closed or ignored while the IME is off. The "always Chinese punctuation" lock, and a Ctrl+. or toolbar toggle made in English mode, still have to convert marks there, as they do on Windows with the IME closed (KeyEventSink.cpp's FUNCTION_PUNCTUATION and FUNCTION_DOUBLE_SINGLE_BYTE branches), so the hosts carry a forward copy of Engine's contract (vendor/MSIME-Engine/contracts/punctuation/policy.h). This is deliberately not the Linux host's chinese_punctuation_mark: that table is the reverse Space rewrite, maps '/' to 、 and has no alternating quotes.
struct EnglishPunctuationState {
  bool double_quote_open = false;
  bool single_quote_open = false;
  int book_title_nesting = 0;
};

inline std::string english_mode_chinese_punctuation(
    char value, EnglishPunctuationState &state) {
  switch (value) {
  case ',': return "，";
  case '.': return "。";
  case '?': return "？";
  case '!': return "！";
  case ';': return "；";
  case ':': return "：";
  case '(': return "（";
  case ')': return "）";
  case '[': return "【";
  case ']': return "】";
  case '\\': return "、";
  case '`': return "·";
  case '$': return "￥";
  case '^': return "……";
  case '_': return "——";
  case '"':
    state.double_quote_open = !state.double_quote_open;
    return state.double_quote_open ? "“" : "”";
  case '\'':
    state.single_quote_open = !state.single_quote_open;
    return state.single_quote_open ? "‘" : "’";
  case '<':
    return state.book_title_nesting++ == 0 ? "《" : "〈";
  case '>':
    // An unmatched '>' leaves the depth at zero, as Engine's policy does.
    if (state.book_title_nesting > 0 && --state.book_title_nesting > 0)
      return "〉";
    return "》";
  default:
    return {};
  }
}

// The fullwidth form of a printable ASCII character as UTF-8: Space becomes U+3000 and 0x21-0x7e sit one block away at U+FF01-U+FF5E. Empty for anything outside printable ASCII.
inline std::string english_mode_fullwidth(char value) {
  const auto byte = static_cast<unsigned char>(value);
  if (byte == 0x20)
    return "\u3000";
  if (byte < 0x21 || byte > 0x7e)
    return {};
  const std::uint32_t code = byte + 0xfee0;
  std::string wide;
  wide.push_back(static_cast<char>(0xe0 | (code >> 12)));
  wide.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
  wide.push_back(static_cast<char>(0x80 | (code & 0x3f)));
  return wide;
}

// What an English-mode key press commits instead of passing through, empty when the key should go to the application unchanged. Windows order: Chinese punctuation first (only while the lock pins it on or a Ctrl+. in English mode turned it on), then fullwidth, which covers printable ASCII including Space (U+3000). Keypad keys never become Chinese punctuation, matching Chinese mode.
inline std::string english_mode_output(char32_t character, bool keypad,
                                       bool chinese_punctuation, bool fullwidth,
                                       EnglishPunctuationState &state) {
  if (character < 0x20 || character > 0x7e)
    return {};
  const auto value = static_cast<char>(character);
  if (chinese_punctuation && !keypad) {
    auto mark = english_mode_chinese_punctuation(value, state);
    if (!mark.empty())
      return mark;
  }
  if (!fullwidth)
    return {};
  return english_mode_fullwidth(value);
}

} // namespace msime::input

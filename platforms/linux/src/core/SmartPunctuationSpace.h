#pragma once
#include "../../../../shared/input/EnglishModeOutput.h"
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace msime::linux_host {

struct SmartPunctuationMapping {
  std::string_view chinese;
  char ascii;
};

// The reversible Space gesture is broader than direct smart punctuation. The
// latter only special-cases , . : beside ASCII letters/digits; this table is
// the Windows product's complete Chinese -> ASCII rewrite contract. Both quote
// halves intentionally map to the same key. Auto-completed pairs are excluded
// by the hosts before they arm the gesture.
inline constexpr SmartPunctuationMapping kSmartPunctuationSpaceMap[] = {
    {"。", '.'}, {"，", ','}, {"！", '!'}, {"？", '?'}, {"；", ';'},
    {"：", ':'}, {"、", '/'}, {"“", '"'},  {"”", '"'},  {"‘", '\''},
    {"’", '\''}, {"【", '['}, {"】", ']'}, {"《", '<'}, {"》", '>'},
    {"（", '('}, {"）", ')'},
};

// The three keys smart punctuation routes: a mark after an ASCII letter or digit
// stays ASCII, otherwise Engine's Chinese table converts it. Shared so the IBus
// and Fcitx5 hosts cannot disagree about which keys those are.
inline constexpr bool is_smart_punctuation_key(char value) {
  return value == ',' || value == '.' || value == ':';
}

// The Chinese mark Engine commits for an ASCII one, empty for a key that has no
// pair here. One table for both hosts and for both rewrites - the repeat back to
// Chinese and the space back to ASCII read the same mapping in opposite
// directions, and a second copy of it would be a second thing to drift.
inline constexpr std::string_view chinese_punctuation_mark(char value) {
  for (const auto &mapping : kSmartPunctuationSpaceMap)
    if (mapping.ascii == value)
      return mapping.chinese;
  return {};
}

inline constexpr char smart_punctuation_ascii_mark(std::string_view chinese) {
  for (const auto &mapping : kSmartPunctuationSpaceMap)
    if (mapping.chinese == chinese)
      return mapping.ascii;
  return 0;
}

inline constexpr bool is_space_conversion_key(char value) {
  return !chinese_punctuation_mark(value).empty();
}

inline constexpr bool is_auto_paired_opening_key(char value) {
  return value == '"' || value == '\'' || value == '(' || value == '[' ||
         value == '<';
}

// Space conversion always writes literal half-width ASCII. It is a rewrite
// gesture, not ordinary character-width output.
inline std::string space_conversion_ascii_text(std::string_view chinese) {
  const auto ascii = smart_punctuation_ascii_mark(chinese);
  return ascii == 0 ? std::string{} : std::string(1, ascii);
}

// An ASCII mark as the host would commit it under the current width setting.
// Printable ASCII has a fullwidth form one block away; nothing else is offered
// here, because nothing else is a mark these rewrites produce.
inline std::string ascii_mark_text(char value, bool fullwidth) {
  const auto byte = static_cast<unsigned char>(value);
  if (!fullwidth || byte < 0x21 || byte > 0x7e)
    return std::string(1, value);
  const std::uint32_t code = byte + 0xfee0;
  std::string wide;
  wide.push_back(static_cast<char>(0xe0 | (code >> 12)));
  wide.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
  wide.push_back(static_cast<char>(0x80 | (code & 0x3f)));
  return wide;
}

// The ASCII mark a committed string stands for, in either width; 0 for anything
// else. The inverse of ascii_mark_text over exactly the marks these rewrites
// touch, so a host can recognise its own commit without keeping a second list of
// keys next to the table.
inline char ascii_mark_from_text(std::string_view text, bool fullwidth) {
  for (char value = 0x21; value <= 0x7e; ++value) {
    if (!is_smart_punctuation_key(value))
      continue;
    const auto candidate = ascii_mark_text(value, fullwidth);
    if (std::string_view(candidate) == text)
      return value;
  }
  return 0;
}

// Whether pressing the same smart-punctuation key again may replace the ASCII
// mark it just committed with the Chinese one.
//
// Weaker than the space conversion's check on purpose, and deliberately not
// strengthened here: this one is guarded by a two-second window and by the key
// being the same one, which the source relies on instead of a fingerprint. The
// only document question is whether that ASCII mark - in whichever width the
// host committed it - is still the character in front of the caret.
inline bool repeat_conversion_matches_document(
    char ascii_mark, bool fullwidth, const std::vector<std::string> &preceding) {
  return !preceding.empty() &&
         preceding.back() == ascii_mark_text(ascii_mark, fullwidth);
}

// Whether a Space may take the Chinese mark in front of the caret back to
// ASCII.
//
// The decision is a document fingerprint, not a timer: the same mark usually
// stands in several places, and moving the caret inside one window is not a
// focus change, so a check that only asked "is a mark in front of the caret"
// would happily rewrite one the user never typed. Both the mark and the
// character it follows have to still be what they were when the mark was
// committed.
//
// `preceding` is the text in front of the caret, oldest first, and holds at
// most the two characters this needs. Fewer than two means the document starts
// there, which agrees with an `armed_preceding` that was empty for the same
// reason; an empty `preceding` means nothing precedes the caret at all and
// there is no mark to rewrite.
inline bool space_conversion_matches_document(
    std::string_view chinese_mark, std::string_view armed_preceding,
    const std::vector<std::string> &preceding) {
  if (chinese_mark.empty() || preceding.empty())
    return false;
  if (std::string_view(preceding.back()) != chinese_mark)
    return false;
  if (armed_preceding.empty())
    return true;
  return preceding.size() >= 2 &&
         std::string_view(preceding.front()) == armed_preceding;
}

// English-mode punctuation and fullwidth output is shared with the macOS host; see shared/input/EnglishModeOutput.h.
using msime::input::english_mode_chinese_punctuation;
using msime::input::english_mode_output;
using msime::input::EnglishPunctuationState;

} // namespace msime::linux_host

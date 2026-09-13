#pragma once
#include <optional>

namespace msime::windows {
// A toolbar button's icon, as the shipped presenter defines it.
//
// Every icon carries a text fallback on purpose. "Segoe Fluent Icons" ships
// with Windows 11 only, and the Windows 10 build of "Segoe MDL2 Assets" may
// predate some of these codepoints. DirectWrite substitutes a font silently
// rather than failing, so a button whose glyph is missing renders as a blank
// box unless something checks first and draws the text instead.
struct ToolbarIcon {
  wchar_t codepoint = 0;
  const wchar_t *fallback = L"";
};
// Button ids as the toolbar's slot order uses them.
enum ToolbarButton {
  kToolbarLanguage = 0,
  kToolbarFullwidth = 1,
  kToolbarPunctuation = 2,
  kToolbarCharacterSet = 3,
  kToolbarEmoji = 4,
  kToolbarScreenKeyboard = 5,
  kToolbarSettings = 6,
  kToolbarVoice = 7,
  kToolbarAbout = 8,
  kToolbarHide = 9,
};
// The icon for one button. `state` is that button's two-way mode - Chinese,
// full width, Chinese punctuation, traditional output - and is absent when the
// Server has not reported it yet. An unreported mode shows a question mark
// rather than a guessed state, which would tell the user the wrong thing.
inline ToolbarIcon toolbar_icon(int button, std::optional<bool> state) {
  const ToolbarIcon unknown{0, L"?"};
  switch (button) {
  case kToolbarLanguage:
    if (!state)
      return unknown;
    return *state ? ToolbarIcon{0xE982, L"中"}   // 中
                  : ToolbarIcon{0xE983, L"英"};  // 英
  case kToolbarFullwidth:
    if (!state)
      return unknown;
    return *state ? ToolbarIcon{0xF138, L"全"}   // 全
                  : ToolbarIcon{0xEC46, L"半"};  // 半
  case kToolbarPunctuation:
    if (!state)
      return unknown;
    return *state ? ToolbarIcon{0xF111, L"。"}   // 。
                  : ToolbarIcon{0xF110, L","};
  case kToolbarCharacterSet:
    if (!state)
      return unknown;
    // state is "traditional output is on".
    return *state ? ToolbarIcon{0xE88C, L"繁"}   // 繁
                  : ToolbarIcon{0xE88D, L"简"};  // 简
  case kToolbarEmoji:
    return {0xE76E, L"表"}; // 表
  case kToolbarScreenKeyboard:
    return {0xE765, L"键"}; // 键
  case kToolbarSettings:
    return {0xE713, L"设"}; // 设
  case kToolbarVoice:
    // No upstream counterpart: the shipped toolbar has no voice button. The
    // microphone codepoint is the standard one both icon fonts carry.
    return {0xE720, L"音"}; // 音
  case kToolbarAbout:
    return {0, L"?"};
  case kToolbarHide:
    return {0, L"×"};
  default:
    return unknown;
  }
}
} // namespace msime::windows

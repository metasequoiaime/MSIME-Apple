#include "ToolbarIcons.h"
#include <cstring>
#include <iostream>
#include <set>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("Toolbar icon table failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
} // namespace
int main() {
  try {
    // Codepoints match the shipped presenter's table exactly.
    require(toolbar_icon(kToolbarLanguage, true).codepoint == 0xE982);
    require(toolbar_icon(kToolbarLanguage, false).codepoint == 0xE983);
    require(toolbar_icon(kToolbarFullwidth, true).codepoint == 0xF138);
    require(toolbar_icon(kToolbarFullwidth, false).codepoint == 0xEC46);
    require(toolbar_icon(kToolbarPunctuation, true).codepoint == 0xF111);
    require(toolbar_icon(kToolbarPunctuation, false).codepoint == 0xF110);
    require(toolbar_icon(kToolbarCharacterSet, true).codepoint == 0xE88C);
    require(toolbar_icon(kToolbarCharacterSet, false).codepoint == 0xE88D);
    require(toolbar_icon(kToolbarEmoji, std::nullopt).codepoint == 0xE76E);
    require(toolbar_icon(kToolbarScreenKeyboard, std::nullopt).codepoint == 0xE765);
    require(toolbar_icon(kToolbarSettings, std::nullopt).codepoint == 0xE713);

    // An unreported mode is a question mark, not a guessed state. Showing 中
    // when the Server has not said so would tell the user the wrong mode.
    for (const int button : {kToolbarLanguage, kToolbarFullwidth,
                             kToolbarPunctuation, kToolbarCharacterSet}) {
      const auto icon = toolbar_icon(button, std::nullopt);
      require(icon.codepoint == 0);
      require(std::wcscmp(icon.fallback, L"?") == 0);
    }

    // Every icon carries a non-empty text fallback: the glyph fonts are not
    // present on every Windows build, and a missing glyph draws a blank box.
    for (int button = kToolbarLanguage; button <= kToolbarHide; ++button)
      for (const std::optional<bool> state :
           {std::optional<bool>{}, std::optional<bool>{true},
            std::optional<bool>{false}}) {
        const auto icon = toolbar_icon(button, state);
        require(icon.fallback != nullptr && icon.fallback[0] != L'\0');
      }

    // The two states of one button must differ, or the toolbar cannot show
    // which mode is active - the whole point of the button.
    for (const int button : {kToolbarLanguage, kToolbarFullwidth,
                             kToolbarPunctuation, kToolbarCharacterSet}) {
      const auto on = toolbar_icon(button, true);
      const auto off = toolbar_icon(button, false);
      require(on.codepoint != off.codepoint);
      require(std::wcscmp(on.fallback, off.fallback) != 0);
    }

    // Distinct buttons must not share a glyph either.
    std::set<wchar_t> seen;
    for (const auto &entry :
         {toolbar_icon(kToolbarLanguage, true), toolbar_icon(kToolbarLanguage, false),
          toolbar_icon(kToolbarFullwidth, true), toolbar_icon(kToolbarFullwidth, false),
          toolbar_icon(kToolbarPunctuation, true), toolbar_icon(kToolbarPunctuation, false),
          toolbar_icon(kToolbarCharacterSet, true), toolbar_icon(kToolbarCharacterSet, false),
          toolbar_icon(kToolbarEmoji, std::nullopt),
          toolbar_icon(kToolbarScreenKeyboard, std::nullopt),
          toolbar_icon(kToolbarSettings, std::nullopt),
          toolbar_icon(kToolbarVoice, std::nullopt)}) {
      require(seen.insert(entry.codepoint).second);
    }

    // About and hide have no upstream counterpart and no glyph, so they stay
    // text. An id outside the table is a question mark rather than a blank.
    require(toolbar_icon(kToolbarAbout, std::nullopt).codepoint == 0);
    require(toolbar_icon(kToolbarHide, std::nullopt).codepoint == 0);
    require(toolbar_icon(99, std::nullopt).codepoint == 0);
    require(std::wcscmp(toolbar_icon(99, true).fallback, L"?") == 0);

    std::cout << "Toolbar icons: glyphs and fallbacks match the shipped set\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Toolbar icon table failed with an unknown error\n";
    return 1;
  }
}

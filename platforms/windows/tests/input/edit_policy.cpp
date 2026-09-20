#include "EditPolicy.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("edit policy failed at line " + std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)

FanyImeNamedpipeData key(unsigned code, wchar_t character, unsigned modifiers = 0) {
  FanyImeNamedpipeData packet{};
  packet.event_type = FanyImePipeEventType::KeyEvent;
  packet.keycode = code;
  packet.wch = static_cast<FanyImeWireChar>(character);
  packet.modifiers_down = modifiers;
  return packet;
}

constexpr unsigned shift = 1u;
constexpr unsigned control = 2u;
} // namespace

int main() {
  try {
    // Letters edit the composition whether or not one is already open - that is
    // how one starts.
    REQUIRE(edit_kind(key('A', 'a'), "none", false) == EditKind::Character);
    REQUIRE(edit_kind(key('A', 'A', shift), "none", true) == EditKind::Character);
    // The keycode and the character have to agree: a letter key carrying
    // something else is not a letter.
    REQUIRE(edit_kind(key('A', '1'), "none", true) == EditKind::None);

    // Nothing edits a composition when the Engine's mode is unknown, and
    // nothing at all is an edit outside a key event.
    REQUIRE(edit_kind(key('A', 'a'), "unknown", true) == EditKind::None);
    FanyImeNamedpipeData not_a_key = key('A', 'a');
    not_a_key.event_type = FanyImePipeEventType::ClientActivated;
    REQUIRE(edit_kind(not_a_key, "none", true) == EditKind::None);

    // Shift is the only modifier an edit may carry: Ctrl and its combinations
    // belong to the native shortcut routes, which run before this.
    //
    // `edit_kind`'s own `modifiers & ~1u` bail is a second statement of that -
    // the key translator already answers CancelAndForward for anything past
    // Shift, so removing the local bail changes none of these. It is kept as
    // this function's own contract rather than a borrowed one; the assertions
    // pin the behaviour, not that line.
    REQUIRE(edit_kind(key('A', 'a', control), "none", true) == EditKind::None);
    REQUIRE(edit_kind(key('A', 'a', control | shift), "none", true) == EditKind::None);

    // Erase and caret movement only while composing: with no composition they
    // are the application's Backspace and arrow keys.
    REQUIRE(edit_kind(key(0x08, '\b'), "none", true) == EditKind::Erase);
    REQUIRE(edit_kind(key(0x2E, '\0'), "none", true) == EditKind::Erase);
    REQUIRE(edit_kind(key(0x25, '\0'), "none", true) == EditKind::Caret);
    REQUIRE(edit_kind(key(0x27, '\0'), "none", true) == EditKind::Caret);
    REQUIRE(edit_kind(key(0x08, '\b'), "none", false) == EditKind::None);
    REQUIRE(edit_kind(key(0x25, '\0'), "none", false) == EditKind::None);
    // With a modifier they are shortcuts, not edits.
    REQUIRE(edit_kind(key(0x25, '\0', control), "none", true) == EditKind::None);

    // The apostrophe is the manual syllable separator, and only while composing
    // in the ordinary mode.
    REQUIRE(edit_kind(key(0xDE, '\''), "none", true) == EditKind::Character);
    REQUIRE(edit_kind(key(0xDE, '\''), "none", false) == EditKind::None);
    REQUIRE(edit_kind(key(0xDE, '\''), "emoji", true) == EditKind::None);

    // Japanese reserves the OEM minus key for the long vowel mark. Elsewhere
    // that key is navigation or punctuation and must not reach the composition.
    REQUIRE(edit_kind(key(0xBD, '-'), "none", true, false, {}, 0, true) ==
            EditKind::Character);
    REQUIRE(edit_kind(key(0xBD, '-'), "none", true, false, {}, 0, false) == EditKind::None);
    // Only while composing, and only on that key.
    REQUIRE(edit_kind(key(0xBD, '-'), "none", false, false, {}, 0, true) == EditKind::None);
    REQUIRE(edit_kind(key(0xBB, '='), "none", true, false, {}, 0, true) == EditKind::None);

    // Microsoft double pinyin puts `ing` on the semicolon. It is a character
    // only at an odd offset inside the syllable being typed - at an even one
    // the syllable has no initial yet and the key is an ordinary semicolon.
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, true, "n", 1) == EditKind::Character);
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, true, "ni", 2) == EditKind::None);
    // The offset is counted from the last separator, not from the start.
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, true, "ni'h", 4) == EditKind::Character);
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, true, "ni'ha", 5) == EditKind::None);
    // A caret past the text is clamped rather than read out of range.
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, true, "n", 99) == EditKind::Character);
    // Without the profile, and outside the ordinary mode, it is not that key.
    REQUIRE(edit_kind(key(0xBA, ';'), "none", true, false, "n", 1) == EditKind::None);
    REQUIRE(edit_kind(key(0xBA, ';'), "emoji", true, true, "n", 1) == EditKind::None);

    // Unicode mode is the one place digits are input rather than candidate
    // shortcuts; Shift+digit stays a selection. That early return is likewise a
    // second statement: falling through reaches neither the digit branch (it
    // requires no modifier) nor the plus branch, and answers None anyway.
    REQUIRE(edit_kind(key('4', '4'), "unicode", true) == EditKind::Character);
    REQUIRE(edit_kind(key('0', '0'), "unicode", true) == EditKind::Character);
    REQUIRE(edit_kind(key('4', '$', shift), "unicode", true) == EditKind::None);
    REQUIRE(edit_kind(key(0xBB, '+', shift), "unicode", true) == EditKind::Character);
    // Outside Unicode mode a digit is a candidate shortcut, not an edit.
    REQUIRE(edit_kind(key('4', '4'), "none", true) == EditKind::None);

    // The preedit style preference maps by name and refuses anything else: a
    // typo must not silently become one of the three.
    REQUIRE(preference_tsf_preedit_style(nlohmann::json::object()) == TsfPreeditStyle::Local);
    REQUIRE(preference_tsf_preedit_style({{"tsf_preedit_style", "raw"}}) ==
            TsfPreeditStyle::Local);
    REQUIRE(preference_tsf_preedit_style({{"tsf_preedit_style", "pinyin"}}) ==
            TsfPreeditStyle::Pinyin);
    REQUIRE(preference_tsf_preedit_style({{"tsf_preedit_style", "empty"}}) ==
            TsfPreeditStyle::Empty);
    bool refused = false;
    try {
      preference_tsf_preedit_style({{"tsf_preedit_style", "Pinyin"}});
    } catch (const std::invalid_argument &) {
      refused = true;
    }
    REQUIRE(refused);

    std::cout << "Windows edit policy checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

#include "../src/system/SharedConfigKeybindings.h"

#include <cassert>
#include <iostream>
#include <string>

using namespace msime::windows;

namespace {
bool has_line(const std::string &text, const std::string &line) {
  const auto full = "\n" + text;
  return full.find("\n" + line + "\n") != std::string::npos ||
         full.find("\n" + line + "\r\n") != std::string::npos;
}

size_t count_occurrences(const std::string &text, const std::string &needle) {
  size_t total = 0;
  for (size_t at = text.find(needle); at != std::string::npos;
       at = text.find(needle, at + needle.size()))
    ++total;
  return total;
}

// The four values have to land in a form ReadConfiguredSwitchLanguateHotkeys
// parses: `key = true` inside [keybindings].
void writes_all_four_keys() {
  SwitchLanguageKeybindings values;
  values.shift = false;
  values.ctrl = true;
  values.ctrl_alt_space = false;
  values.character_set_ctrl_shift_f = true;
  const auto text = update_keybindings("", values);
  assert(has_line(text, "[keybindings]"));
  assert(has_line(text, "switch_language_shift = false"));
  assert(has_line(text, "switch_language_ctrl = true"));
  assert(has_line(text, "switch_language_ctrl_alt_space = false"));
  assert(has_line(text, "toggle_character_set_ctrl_shift_f = true"));
}

// The user's file is not ours. Everything we do not own survives untouched.
void preserves_other_sections_and_comments() {
  const std::string original =
      "# My config\n"
      "[input]\n"
      "mode = \"japanese\"  # stay in kana\n"
      "punctuation_lock = \"chinese\"\n"
      "\n"
      "[appearance]\n"
      "skin = \"wechat\"\n";
  const auto text = update_keybindings(original, {});
  assert(has_line(text, "# My config"));
  assert(has_line(text, "[input]"));
  assert(has_line(text, "mode = \"japanese\"  # stay in kana"));
  assert(has_line(text, "punctuation_lock = \"chinese\""));
  assert(has_line(text, "[appearance]"));
  assert(has_line(text, "skin = \"wechat\""));
  // And the section we do own is added.
  assert(has_line(text, "[keybindings]"));
  assert(has_line(text, "switch_language_shift = true"));
}

// Updating in place, not appending a second copy: two assignments for one key
// would leave the file's meaning depending on parse order.
void replaces_existing_values_in_place() {
  const std::string original =
      "[keybindings]\n"
      "switch_language_shift = true\n"
      "switch_language_ctrl = true\n"
      "toggle_character_set_ctrl_shift_f = true\n";
  SwitchLanguageKeybindings values;
  values.shift = false;
  values.ctrl = false;
  values.ctrl_alt_space = true;
  values.character_set_ctrl_shift_f = false;
  const auto text = update_keybindings(original, values);
  assert(count_occurrences(text, "switch_language_shift ") == 1);
  assert(count_occurrences(text, "toggle_character_set_ctrl_shift_f ") == 1);
  assert(has_line(text, "switch_language_shift = false"));
  assert(has_line(text, "switch_language_ctrl = false"));
  assert(has_line(text, "toggle_character_set_ctrl_shift_f = false"));
  // The one key that was missing is added rather than dropped.
  assert(has_line(text, "switch_language_ctrl_alt_space = true"));
  // switch_language_ctrl_alt_space must not be confused with
  // switch_language_ctrl: a prefix match would have overwritten the wrong key.
  assert(count_occurrences(text, "switch_language_ctrl = ") == 1);
  assert(count_occurrences(text, "switch_language_ctrl_alt_space = ") == 1);
}

// Keys appended to an existing section belong inside it. Landing them after a
// later section header would silently reassign them to that section.
void appends_inside_the_section_not_at_the_end_of_the_file() {
  const std::string original =
      "[keybindings]\n"
      "switch_language_shift = true\n"
      "[input]\n"
      "mode = \"pinyin\"\n";
  const auto text = update_keybindings(original, {});
  const auto keybindings = text.find("[keybindings]");
  const auto input = text.find("[input]");
  assert(keybindings != std::string::npos && input != std::string::npos);
  assert(keybindings < input);
  // Every key we wrote sits between the two headers.
  for (const std::string key : {"switch_language_shift",
                                "switch_language_ctrl",
                                "switch_language_ctrl_alt_space",
                                "toggle_character_set_ctrl_shift_f"}) {
    const auto at = text.find(key + " =");
    assert(at != std::string::npos);
    assert(at > keybindings && at < input);
  }
  // [input] and its contents are still intact after all that insertion.
  assert(has_line(text, "mode = \"pinyin\""));
}

// The TIP strips comments before parsing. So must we, or a commented-out key
// would be "found", left in place, and the real value never written.
void commented_keys_do_not_shadow_the_real_ones() {
  const std::string original =
      "[keybindings]\n"
      "# switch_language_shift = true\n"
      "switch_language_ctrl = false\n";
  SwitchLanguageKeybindings values;
  values.shift = false;
  const auto text = update_keybindings(original, values);
  // The comment survives verbatim...
  assert(has_line(text, "# switch_language_shift = true"));
  // ...and a real assignment is added rather than skipped.
  assert(has_line(text, "switch_language_shift = false"));
}

// The legacy array is what the TIP falls back to only when the explicit keys
// are absent. We always write them, so it is inert - but it is the user's line
// and we do not delete it.
void legacy_array_is_left_alone() {
  const std::string original =
      "[keybindings]\n"
      "switch_language = [\"Ctrl+Space\", \"Shift\"]\n";
  const auto text = update_keybindings(original, {});
  assert(has_line(text, "switch_language = [\"Ctrl+Space\", \"Shift\"]"));
  assert(has_line(text, "switch_language_shift = true"));
  // The legacy key is not mistaken for one of ours.
  assert(count_occurrences(text, "switch_language = [") == 1);
}

// A duplicate key is ambiguous; collapse it rather than propagating it.
void duplicate_assignments_collapse_to_one() {
  const std::string original =
      "[keybindings]\n"
      "switch_language_shift = true\n"
      "switch_language_shift = false\n";
  const auto text = update_keybindings(original, {});
  assert(count_occurrences(text, "switch_language_shift = ") == 1);
  assert(has_line(text, "switch_language_shift = true"));
}

// Rewriting must not convert a user's whole file to the other line ending.
void line_endings_are_preserved() {
  const auto crlf = update_keybindings("[input]\r\nmode = \"pinyin\"\r\n", {});
  assert(crlf.find("\r\n") != std::string::npos);
  assert(count_occurrences(crlf, "\n") == count_occurrences(crlf, "\r\n"));
  const auto lf = update_keybindings("[input]\nmode = \"pinyin\"\n", {});
  assert(lf.find('\r') == std::string::npos);
}

// Whatever we write has to parse back the way the TIP reads it. Round-tripping
// through the function twice must be a no-op, or repeated saves would grow the
// file without bound.
void rewriting_is_idempotent() {
  SwitchLanguageKeybindings values;
  values.ctrl = true;
  values.ctrl_alt_space = false;
  const std::string original = "[input]\nmode = \"pinyin\"\n";
  const auto once = update_keybindings(original, values);
  const auto twice = update_keybindings(once, values);
  assert(once == twice);
  // And a different value changes only that value.
  values.ctrl = false;
  const auto changed = update_keybindings(once, values);
  assert(changed != once);
  assert(has_line(changed, "switch_language_ctrl = false"));
  assert(has_line(changed, "switch_language_ctrl_alt_space = false"));
  assert(has_line(changed, "mode = \"pinyin\""));
}

// Degenerate inputs must not produce a file that loses the user's settings.
void handles_files_without_trailing_newlines() {
  const auto no_newline = update_keybindings("[input]\nmode = \"pinyin\"", {});
  assert(has_line(no_newline, "mode = \"pinyin\""));
  assert(has_line(no_newline, "[keybindings]"));
  // The section header must not have been glued onto the previous line.
  assert(no_newline.find("\"pinyin\"[keybindings]") == std::string::npos);
  const auto blank = update_keybindings("\n\n", {});
  assert(has_line(blank, "[keybindings]"));
}
} // namespace

int main() {
  writes_all_four_keys();
  preserves_other_sections_and_comments();
  replaces_existing_values_in_place();
  appends_inside_the_section_not_at_the_end_of_the_file();
  commented_keys_do_not_shadow_the_real_ones();
  legacy_array_is_left_alone();
  duplicate_assignments_collapse_to_one();
  line_endings_are_preserved();
  rewriting_is_idempotent();
  handles_files_without_trailing_newlines();
  std::cout << "Shared config keybindings: the TIP's hotkeys follow settings\n";
  return 0;
}

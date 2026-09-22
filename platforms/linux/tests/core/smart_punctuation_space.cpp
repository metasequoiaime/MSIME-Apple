#include "../src/core/SmartPunctuationSpace.h"

#include <cassert>
#include <string>
#include <vector>

using msime::linux_host::ascii_mark_from_text;
using msime::linux_host::ascii_mark_text;
using msime::linux_host::chinese_punctuation_mark;
using msime::linux_host::is_auto_paired_opening_key;
using msime::linux_host::is_smart_punctuation_key;
using msime::linux_host::is_space_conversion_key;
using msime::linux_host::repeat_conversion_matches_document;
using msime::linux_host::smart_punctuation_ascii_mark;
using msime::linux_host::space_conversion_ascii_text;
using msime::linux_host::space_conversion_matches_document;

int main() {
  const std::vector<std::string> after_letter{"好", "，"};
  // The mark is still the one that was committed, still after the same
  // character: this is the mark the user just typed.
  assert(space_conversion_matches_document("，", "好", after_letter));
  // Same mark, different neighbour - the caret moved to another comma in the
  // document, and rewriting it would edit text the user already accepted.
  assert(!space_conversion_matches_document("，", "刚", after_letter));
  // A different mark in front of the caret is not this key's mark.
  assert(!space_conversion_matches_document("。", "好", after_letter));

  // No fingerprint could be taken - the mark opened the document, or the host
  // published no readable text in front of the caret. There is then nothing for
  // the readback to disagree with, and the mark match alone decides, which is
  // the rule the source settled on rather than disabling the feature in those
  // hosts.
  const std::vector<std::string> alone{"，"};
  assert(space_conversion_matches_document("，", "", alone));
  assert(space_conversion_matches_document("，", "", after_letter));
  // A fingerprint was recorded, so a mark that now opens the document is not
  // the one that was armed.
  assert(!space_conversion_matches_document("，", "好", alone));

  // Nothing in front of the caret leaves no mark to rewrite.
  assert(!space_conversion_matches_document("，", "好", {}));
  assert(!space_conversion_matches_document("，", "", {}));
  // A key with no Chinese mark never arms, and never matches if it somehow did.
  assert(!space_conversion_matches_document("", "好", after_letter));

  // The three keys smart punctuation routes, and only those.
  assert(is_smart_punctuation_key(',') && is_smart_punctuation_key('.') &&
         is_smart_punctuation_key(':'));
  assert(!is_smart_punctuation_key(';') && !is_smart_punctuation_key('!') &&
         !is_smart_punctuation_key('a') && !is_smart_punctuation_key(' '));

  // Direct smart routing remains the narrow three-key policy.
  assert(chinese_punctuation_mark(',') == "，");
  assert(chinese_punctuation_mark('.') == "。");
  assert(chinese_punctuation_mark(':') == "：");
  assert(chinese_punctuation_mark('<') == "《");
  assert(chinese_punctuation_mark('a').empty());
  assert(chinese_punctuation_mark(' ').empty());

  // Space conversion follows the complete Windows mapping. Both halves of a
  // quote map to the same ASCII key; braces and corner brackets are not part of
  // the product contract.
  const std::vector<std::pair<std::string_view, char>> conversions{
      {"。", '.'}, {"，", ','}, {"！", '!'}, {"？", '?'}, {"；", ';'},
      {"：", ':'}, {"、", '/'}, {"“", '"'},  {"”", '"'},  {"‘", '\''},
      {"’", '\''}, {"【", '['}, {"】", ']'}, {"《", '<'}, {"》", '>'},
      {"（", '('}, {"）", ')'},
  };
  for (const auto &[chinese, ascii] : conversions) {
    assert(smart_punctuation_ascii_mark(chinese) == ascii);
    assert(is_space_conversion_key(ascii));
    assert(space_conversion_ascii_text(chinese) == std::string(1, ascii));
  }
  assert(smart_punctuation_ascii_mark("〈") == 0);
  assert(smart_punctuation_ascii_mark("｛") == 0);
  assert(!is_space_conversion_key('{'));
  assert(space_conversion_ascii_text("x").empty());
  assert(is_auto_paired_opening_key('"'));
  assert(is_auto_paired_opening_key('\''));
  assert(is_auto_paired_opening_key('('));
  assert(is_auto_paired_opening_key('['));
  assert(is_auto_paired_opening_key('<'));
  assert(!is_auto_paired_opening_key(')'));
  assert(!is_auto_paired_opening_key('/'));

  // Half width leaves the key alone; full width moves printable ASCII one block
  // up, which is what the host would have committed in the first place.
  assert(ascii_mark_text(',', false) == ",");
  assert(ascii_mark_text('.', false) == ".");
  assert(ascii_mark_text('.', true) == "\uff0e");
  assert(ascii_mark_text(':', true) == "\uff1a");
  // Ordinary repeat routing still recognises the width Engine committed.
  assert(ascii_mark_text(',', true) == chinese_punctuation_mark(','));
  assert(ascii_mark_text('.', true) != chinese_punctuation_mark('.'));
  // Nothing outside printable ASCII has a fullwidth form to offer.
  assert(ascii_mark_text('\n', true) == std::string(1, '\n'));

  // Recognising the host's own commit, so the repeat gesture can arm without a
  // second list of keys beside the table.
  assert(ascii_mark_from_text(",", false) == ',');
  assert(ascii_mark_from_text("．", true) == '.');
  assert(ascii_mark_from_text("a", false) == 0);
  assert(ascii_mark_from_text("", false) == 0);
  // A halfwidth comma is not what a fullwidth host committed, and the fullwidth
  // comma is - the same codepoint as the Chinese one, which is why the repeat
  // gesture is guarded by the key and the window rather than by the glyph alone.
  assert(ascii_mark_from_text(",", true) == 0);
  assert(ascii_mark_from_text("，", true) == ',');
  // Space conversion never consults the character-width mode.
  assert(space_conversion_ascii_text("，") == ",");
  assert(space_conversion_ascii_text("。") == ".");

  // The repeat check asks one question of the document: is that ASCII mark, in
  // the width the host committed it, still in front of the caret.
  assert(repeat_conversion_matches_document(',', false, {"a", ","}));
  assert(!repeat_conversion_matches_document(',', false, {"a", "."}));
  assert(!repeat_conversion_matches_document(',', false, {}));
  assert(repeat_conversion_matches_document('.', true, {"．"}));
  assert(!repeat_conversion_matches_document('.', true, {"."}));
  return 0;
}

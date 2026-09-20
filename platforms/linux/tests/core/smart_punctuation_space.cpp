#include "../src/core/SmartPunctuationSpace.h"

#include <cassert>
#include <string>
#include <vector>

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
  return 0;
}

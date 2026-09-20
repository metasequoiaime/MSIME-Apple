#pragma once
#include <string>
#include <string_view>
#include <vector>

namespace msime::linux_host {

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

} // namespace msime::linux_host

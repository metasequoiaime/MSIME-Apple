#pragma once

#include "../../../../shared/input/GlossSenses.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::linux_host {

// The dictionary joins multiple senses with either an ASCII or a full-width semicolon; IBus and Fcitx5 present them as the same secondary translation choices. The rule is shared with every other host - see shared/input/GlossSenses.h.
inline std::vector<std::string>
split_translation_gloss(std::string_view gloss) {
  return msime::input::gloss_senses(gloss);
}

// Folds the user's own translator's answers into a non-English offline dictionary's glosses for the same page.
//
// The dictionary answers at once and is shown first; the provider is then asked about every candidate, not only the dictionary's misses as on the English path, because the shared translation query ranks the user's own translator above an installed dictionary. So an online gloss replaces the dictionary's for the same text in place, a text only the provider answered is appended, and the dictionary keeps whatever the provider left.
inline void prefer_online_glosses(
    std::vector<std::pair<std::string, std::string>> &glosses,
    const std::vector<std::pair<std::string, std::string>> &online) {
  for (const auto &entry : online) {
    if (entry.first.empty() || entry.second.empty())
      continue;
    const auto existing = std::find_if(
        glosses.begin(), glosses.end(),
        [&](const auto &item) { return item.first == entry.first; });
    if (existing == glosses.end())
      glosses.push_back(entry);
    else
      existing->second = entry.second;
  }
}

} // namespace msime::linux_host

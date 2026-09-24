#pragma once

#include <algorithm>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::linux_host {

// The Windows dictionary joins multiple senses with either an ASCII or a
// full-width semicolon. Keep this policy host-independent so IBus and Fcitx5
// can present the same secondary translation choices.
inline std::vector<std::string>
split_translation_gloss(std::string_view gloss) {
  static constexpr std::string_view fullwidth_separator = "\xEF\xBC\x9B";
  std::vector<std::string> senses;
  size_t start = 0;
  const auto append = [&senses](std::string_view value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string_view::npos)
      return;
    const auto last = value.find_last_not_of(" \t\r\n");
    senses.emplace_back(value.substr(first, last - first + 1));
  };
  while (start <= gloss.size()) {
    const auto ascii = gloss.find(';', start);
    const auto fullwidth = gloss.find(fullwidth_separator, start);
    const auto cut = std::min(ascii, fullwidth);
    if (cut == std::string_view::npos) {
      append(gloss.substr(start));
      break;
    }
    append(gloss.substr(start, cut - start));
    start = cut + (cut == fullwidth ? fullwidth_separator.size() : 1);
  }
  return senses;
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

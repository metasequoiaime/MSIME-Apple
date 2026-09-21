#pragma once

#include <algorithm>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::windows {

// English dictionary glosses use ';' while Chinese glosses use the full-width
// semicolon. Ctrl+Enter commits the first non-empty sense, matching the
// Windows candidate translation policy without leaking joined display text.
inline std::vector<std::string> translation_senses(std::string_view value) {
  static constexpr std::string_view fullwidth = "\xEF\xBC\x9B";
  std::vector<std::string> senses;
  size_t start = 0;
  while (start <= value.size()) {
    const auto ascii = value.find(';', start);
    const auto wide = value.find(fullwidth, start);
    const auto cut = ascii == std::string_view::npos
                         ? wide
                         : (wide == std::string_view::npos
                                ? ascii
                                : (std::min)(ascii, wide));
    const auto end = cut == std::string_view::npos ? value.size() : cut;
    const auto first = value.find_first_not_of(" \t\r\n", start);
    if (first != std::string_view::npos && first < end) {
      const auto last = value.find_last_not_of(" \t\r\n", end - 1);
      senses.emplace_back(value.substr(first, last - first + 1));
    }
    if (cut == std::string_view::npos)
      break;
    start = cut + (cut == wide ? fullwidth.size() : 1);
  }
  return senses;
}

inline std::string first_translation_sense(std::string value) {
  const auto senses = translation_senses(value);
  return senses.empty() ? std::string{} : senses.front();
}

// Which of the planned candidates still need an online provider.
//
// The worker resolves the packaged English glosses first and asks a provider only about what is
// left, which is what the source worker does. Getting it wrong is invisible in both directions:
// asking again for a text that already has a gloss spends a request and, since provider answers are
// appended to the same list, can leave one candidate carrying two glosses; skipping a text that has
// none leaves that candidate blank with a provider configured and reachable.
//
// `answered` is the local result. A text counts as answered only with a gloss attached - an entry
// with an empty one is a candidate nobody has answered yet. The shared gloss request already drops
// empty glosses before the worker sees them, so that half cannot be exercised from there today; it
// is this function's contract rather than a second line of defence.
//
// Order is the plan's, and a text planned twice is asked about once: both are properties the caller
// depends on, since it walks the result against a provider batch.
inline std::vector<std::string> untranslated_texts(
    const std::vector<std::pair<std::string, std::string>> &answered,
    const std::vector<std::string> &planned) {
  std::vector<std::string> pending;
  for (const auto &text : planned) {
    if (text.empty())
      continue;
    const auto done = std::any_of(
        answered.begin(), answered.end(), [&](const auto &entry) {
          return entry.first == text && !entry.second.empty();
        });
    if (done || std::find(pending.begin(), pending.end(), text) != pending.end())
      continue;
    pending.push_back(text);
  }
  return pending;
}

} // namespace msime::windows

#pragma once

#include "../../../../shared/input/GlossSenses.h"

#include <algorithm>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::windows {

// English dictionary glosses use ';' while Chinese glosses use the full-width semicolon. Ctrl+Enter commits the first non-empty sense, without leaking joined display text. The rule is shared with every other host - see shared/input/GlossSenses.h.
inline std::vector<std::string> translation_senses(std::string_view value) {
  return msime::input::gloss_senses(value);
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

// Adds a non-English offline dictionary's glosses to what the user's own translator answered for the same target.
//
// The precedence is the reverse of the English path above, and deliberately so: the shared translation query documents that an online answer outranks an installed dictionary for these targets, so the dictionary only fills the candidates left without a gloss. A text already answered keeps its online gloss and gets no second one, an entry with an empty gloss takes the dictionary's in place, and the dictionary's other texts follow the answers in its own order.
inline void fill_offline_glosses(
    std::vector<std::pair<std::string, std::string>> &answered,
    const std::vector<std::pair<std::string, std::string>> &offline) {
  for (const auto &entry : offline) {
    if (entry.first.empty() || entry.second.empty())
      continue;
    const auto existing = std::find_if(
        answered.begin(), answered.end(),
        [&](const auto &item) { return item.first == entry.first; });
    if (existing == answered.end())
      answered.push_back(entry);
    else if (existing->second.empty())
      existing->second = entry.second;
  }
}

} // namespace msime::windows

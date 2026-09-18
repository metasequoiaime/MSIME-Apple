#pragma once

#include <algorithm>
#include <string>
#include <string_view>
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

} // namespace msime::windows

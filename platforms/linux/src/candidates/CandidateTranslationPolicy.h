#pragma once

#include <algorithm>
#include <string>
#include <string_view>
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

} // namespace msime::linux_host

#pragma once

#include <algorithm>
#include <string>

namespace msime::windows {

// English dictionary glosses use ';' while Chinese glosses use the full-width
// semicolon. Ctrl+Enter commits the first non-empty sense, matching the
// Windows candidate translation policy without leaking joined display text.
inline std::string first_translation_sense(std::string value) {
  const auto fullwidth = value.find("\xEF\xBC\x9B");
  const auto ascii = value.find(';');
  const auto cut = fullwidth == std::string::npos
                       ? ascii
                       : (ascii == std::string::npos
                              ? fullwidth
                              : (std::min)(ascii, fullwidth));
  if (cut != std::string::npos)
    value.resize(cut);
  const auto first = value.find_first_not_of(" \t\r\n");
  if (first == std::string::npos)
    return {};
  const auto last = value.find_last_not_of(" \t\r\n");
  return value.substr(first, last - first + 1);
}

} // namespace msime::windows

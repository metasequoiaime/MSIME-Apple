#pragma once

#include <cstddef>
#include <string>

// Input is UTF-8. Keep a byte limit without splitting the last code point.
inline void msime_clipboard_truncate(std::string &text, size_t limit) {
  if (text.size() <= limit)
    return;
  while (limit > 0 &&
         (static_cast<unsigned char>(text[limit]) & 0xc0) == 0x80)
    --limit;
  text.resize(limit);
}

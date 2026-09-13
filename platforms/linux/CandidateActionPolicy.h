#pragma once

#include <cstddef>
#include <cstdint>
#include <string_view>

namespace msime::linux_host {

// Windows deliberately omits deletion for a one-code-point candidate. IBus
// exposes candidate actions through its property menu instead of a per-row
// context menu, but the persistent dictionary operation keeps the same rule.
inline bool candidate_removal_available(std::string_view text) {
  std::size_t count = 0;
  for (std::size_t offset = 0; offset < text.size();) {
    const auto first = static_cast<std::uint8_t>(text[offset]);
    std::size_t width = 0;
    std::uint32_t code_point = 0;
    if (first < 0x80) {
      width = 1;
      code_point = first;
    } else if (first >= 0xc2 && first <= 0xdf) {
      width = 2;
      code_point = first & 0x1f;
    } else if (first >= 0xe0 && first <= 0xef) {
      width = 3;
      code_point = first & 0x0f;
    } else if (first >= 0xf0 && first <= 0xf4) {
      width = 4;
      code_point = first & 0x07;
    } else {
      return false;
    }
    if (offset + width > text.size())
      return false;
    for (std::size_t index = 1; index < width; ++index) {
      const auto byte = static_cast<std::uint8_t>(text[offset + index]);
      if ((byte & 0xc0) != 0x80)
        return false;
      code_point = (code_point << 6) | (byte & 0x3f);
    }
    if ((width == 2 && code_point < 0x80) ||
        (width == 3 && code_point < 0x800) ||
        (width == 4 && code_point < 0x10000) || code_point > 0x10ffff ||
        (code_point >= 0xd800 && code_point <= 0xdfff))
      return false;
    offset += width;
    if (++count > 1)
      return true;
  }
  return false;
}

inline bool candidate_dictionary_removal_available(std::uint64_t scheme,
                                                   std::uint64_t source,
                                                   std::string_view text) {
  return scheme != 3 && (source == 0 || source == 1 || source == 4) &&
         candidate_removal_available(text);
}

} // namespace msime::linux_host

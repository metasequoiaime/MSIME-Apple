#pragma once
#include <string>
#include <string_view>

namespace msime::windows {
// Host ABI forbids controls and bounds this UTF-8 field to 4096 bytes. Preserve
// complete rows instead of truncating bytes through a possible UTF-8 codepoint.
inline std::string append_translation_display(std::string first,
                                              std::string_view next) {
  constexpr size_t maximum = 4096;
  constexpr std::string_view separator = " / ";
  if (first.size() > maximum)
    return {};
  if (next.empty() || next.size() > maximum)
    return first;
  if (first.empty())
    return std::string(next);
  if (separator.size() + next.size() <= maximum - first.size()) {
    first.append(separator);
    first.append(next);
  }
  return first;
}
} // namespace msime::windows

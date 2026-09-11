#pragma once
#include <algorithm>
#include <cstddef>
#include <string_view>

namespace msime::tsf {
// TSF strings use UTF-16 code units. Preserve the Windows client's separator
// mapping while accepting the authoritative raw caret from either input path.
inline std::size_t MapPreeditCaret(std::wstring_view raw, std::size_t rawCaret,
                                  std::wstring_view preedit, std::size_t prefixLength) {
    rawCaret = (std::min)(rawCaret, raw.size());
    std::size_t lettersBeforeCaret = 0;
    for (std::size_t i = 0; i < rawCaret; ++i)
        if (raw[i] != L'\'') ++lettersBeforeCaret;
    std::size_t position = (std::min)(prefixLength, preedit.size());
    std::size_t seenLetters = 0;
    while (position < preedit.size() && seenLetters < lettersBeforeCaret) {
        if (preedit[position] != L'\'') ++seenLetters;
        ++position;
    }
    if (rawCaret > 0 && raw[rawCaret - 1] == L'\'')
        while (position < preedit.size() && preedit[position] == L'\'') ++position;
    return position;
}
} // namespace msime::tsf

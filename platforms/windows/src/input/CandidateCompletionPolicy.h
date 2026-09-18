#pragma once

#include <cstdint>

namespace msime::windows {

// Shared Engine CandidateSource values. These sources represent complete
// results in the Windows server; database/UserDatabase and AI candidates may
// still consume only part of the pinyin composition.
constexpr bool candidate_finishes_composition(uint8_t source) noexcept {
  return source == 2u ||  // CloudSuggestion
         source == 4u ||  // EnglishDictionary
         source == 5u ||  // QuickPhrase
         source == 6u ||  // Emoji
         source == 7u ||  // Kaomoji
         source == 8u;    // Generated sentence
}

} // namespace msime::windows

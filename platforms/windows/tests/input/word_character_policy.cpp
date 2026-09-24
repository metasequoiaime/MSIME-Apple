#include "WordCharacterPolicy.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("word-to-character policy failed at line " +
                             std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)

FanyImeNamedpipeData key(unsigned code, wchar_t character, unsigned modifiers = 0) {
  FanyImeNamedpipeData packet{};
  packet.event_type = FanyImePipeEventType::KeyEvent;
  packet.keycode = code;
  packet.wch = static_cast<FanyImeWireChar>(character);
  packet.modifiers_down = modifiers;
  return packet;
}

template <class F> bool refuses(F action) {
  try {
    action();
  } catch (const std::invalid_argument &) {
    return true;
  }
  return false;
}
} // namespace

int main() {
  try {
    // The preference. An absent block is off, which is what an older
    // configuration has.
    REQUIRE(preference_word_character(nlohmann::json::object()) ==
            WordCharacterBinding::Disabled);
    REQUIRE(preference_word_character(
                {{"word_character", {{"enabled", true}, {"keys", "brackets"}}}}) ==
            WordCharacterBinding::Brackets);
    REQUIRE(preference_word_character(
                {{"word_character", {{"enabled", true}, {"keys", "minus_equal"}}}}) ==
            WordCharacterBinding::MinusEqual);
    // Disabled wins over whichever keys are stored, but the keys are still
    // validated: a configuration naming keys this build does not know is a
    // disagreement to report, not something to quietly treat as off.
    REQUIRE(preference_word_character(
                {{"word_character", {{"enabled", false}, {"keys", "brackets"}}}}) ==
            WordCharacterBinding::Disabled);
    REQUIRE(refuses([] {
      preference_word_character({{"word_character", {{"enabled", false}, {"keys", "commas"}}}});
    }));
    REQUIRE(refuses([] {
      preference_word_character({{"word_character", {{"enabled", true}, {"keys", "Brackets"}}}});
    }));

    // Brackets: the left one takes the first Han character, the right one the
    // last. That direction is the whole feature.
    REQUIRE(word_character_edge(key(0xDB, '['), WordCharacterBinding::Brackets) ==
            MSIME_FIRST_HAN);
    REQUIRE(word_character_edge(key(0xDD, ']'), WordCharacterBinding::Brackets) ==
            MSIME_LAST_HAN);
    // Minus and equals, under their own binding.
    REQUIRE(word_character_edge(key(0xBD, '-'), WordCharacterBinding::MinusEqual) ==
            MSIME_FIRST_HAN);
    REQUIRE(word_character_edge(key(0xBB, '='), WordCharacterBinding::MinusEqual) ==
            MSIME_LAST_HAN);

    // In the Japanese scheme '-' is the long-vowel mark, not the first character; '=' still takes the last.
    REQUIRE(!word_character_edge(key(0xBD, '-'), WordCharacterBinding::MinusEqual, true));
    REQUIRE(word_character_edge(key(0xBB, '='), WordCharacterBinding::MinusEqual, true) ==
            MSIME_LAST_HAN);
    REQUIRE(word_character_edge(key(0xDB, '['), WordCharacterBinding::Brackets, true) ==
            MSIME_FIRST_HAN);

    // One binding does not answer for the other's keys: with minus/equals
    // chosen, a bracket is an ordinary bracket.
    REQUIRE(!word_character_edge(key(0xDB, '['), WordCharacterBinding::MinusEqual));
    REQUIRE(!word_character_edge(key(0xBD, '-'), WordCharacterBinding::Brackets));
    // Off means off.
    REQUIRE(!word_character_edge(key(0xDB, '['), WordCharacterBinding::Disabled));
    REQUIRE(!word_character_edge(key(0xBD, '-'), WordCharacterBinding::Disabled));

    // The keycode and the character must agree. A layout where the bracket
    // keycode carries something else is not this shortcut.
    REQUIRE(!word_character_edge(key(0xDB, '{'), WordCharacterBinding::Brackets));
    REQUIRE(!word_character_edge(key(0xBD, '_'), WordCharacterBinding::MinusEqual));

    // Any modifier makes it something else - these are bare keys.
    REQUIRE(!word_character_edge(key(0xDB, '[', 1), WordCharacterBinding::Brackets));
    REQUIRE(!word_character_edge(key(0xDB, '[', 2), WordCharacterBinding::Brackets));

    // While the TSF's own candidate list is up, the brackets are its paging
    // keys; taking a character out of a word there would be a different action
    // from the one the user is looking at.
    REQUIRE(!word_character_edge(key(0xDB, '[', PipeMetadata::CandidateActive),
                                 WordCharacterBinding::Brackets));

    // Only key events.
    FanyImeNamedpipeData not_a_key = key(0xDB, '[');
    not_a_key.event_type = FanyImePipeEventType::ClientActivated;
    REQUIRE(!word_character_edge(not_a_key, WordCharacterBinding::Brackets));

    // A binding value from outside the enum is a programming error, not an
    // input to guess at.
    REQUIRE(refuses([] {
      word_character_edge(key(0xDB, '['), static_cast<WordCharacterBinding>(9));
    }));

    std::cout << "Windows word-to-character policy checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

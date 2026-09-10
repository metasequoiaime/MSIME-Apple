#pragma once
#include "KeyEvent.h"
#include <nlohmann/json.hpp>
#include <optional>
#include <stdexcept>

namespace msime::windows {
enum class WordCharacterBinding { Disabled, Brackets, MinusEqual };
inline WordCharacterBinding
preference_word_character(const nlohmann::json &preferences) {
  if (!preferences.contains("word_character"))
    return WordCharacterBinding::Disabled;
  const auto &value = preferences.at("word_character");
  const auto keys = value.at("keys").get<std::string>();
  if (keys != "brackets" && keys != "minus_equal")
    throw std::invalid_argument("Invalid shared word-to-character keys");
  if (!value.at("enabled").get<bool>())
    return WordCharacterBinding::Disabled;
  return keys == "brackets" ? WordCharacterBinding::Brackets
                            : WordCharacterBinding::MinusEqual;
}
inline std::optional<uint8_t>
word_character_edge(const FanyImeNamedpipeData &packet,
                    WordCharacterBinding binding) {
  if (binding != WordCharacterBinding::Disabled &&
      binding != WordCharacterBinding::Brackets &&
      binding != WordCharacterBinding::MinusEqual)
    throw std::invalid_argument("Invalid word-to-character binding");
  if (binding == WordCharacterBinding::Disabled ||
      packet.event_type != FanyImePipeEventType::KeyEvent ||
      (packet.modifiers_down & ~FanyImePipeFlags::UiLess) != 0)
    return std::nullopt;
  const bool minus = binding == WordCharacterBinding::MinusEqual;
  if (packet.keycode == (minus ? 0xBDu : 0xDBu) &&
      packet.wch == (minus ? '-' : '['))
    return MSIME_FIRST_HAN;
  if (packet.keycode == (minus ? 0xBBu : 0xDDu) &&
      packet.wch == (minus ? '=' : ']'))
    return MSIME_LAST_HAN;
  return std::nullopt;
}
} // namespace msime::windows

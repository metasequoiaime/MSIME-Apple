#pragma once
#include "msime_client.h"
#include <ibus.h>
#include <nlohmann/json.hpp>
#include <optional>
#include <stdexcept>

namespace msime::linux_host {
struct WordCharacterBinding {
  bool enabled = false;
  bool minus_equal = false;

  static WordCharacterBinding read(const nlohmann::json &preferences) {
    if (!preferences.contains("word_character"))
      return {};
    const auto &value = preferences.at("word_character");
    auto keys = value.at("keys").get<std::string>();
    if (keys != "brackets" && keys != "minus_equal")
      throw std::invalid_argument("Invalid word-to-character binding");
    return {value.at("enabled").get<bool>(), keys == "minus_equal"};
  }

  std::optional<uint8_t> edge(guint key, bool shift) const {
    if (!enabled || shift)
      return std::nullopt;
    if (key == (minus_equal ? IBUS_minus : IBUS_bracketleft))
      return MSIME_FIRST_HAN;
    if (key == (minus_equal ? IBUS_equal : IBUS_bracketright))
      return MSIME_LAST_HAN;
    return std::nullopt;
  }
};
} // namespace msime::linux_host

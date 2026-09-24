#pragma once
#include <nlohmann/json.hpp>
#include <optional>
#include <string>

namespace msime::windows {
struct CandidateLayoutSettings {
  bool horizontal = false;
  bool show_preedit = true;
  // The shared `wubi_code_hint`, which is on when the document does not say.
  bool wubi_code_hint = true;
  // The switches travel in one atomic value between monitor and UI threads.
  constexpr unsigned encode() const {
    return (horizontal ? 1u : 0u) | (show_preedit ? 2u : 0u) | (wubi_code_hint ? 4u : 0u);
  }
  static constexpr CandidateLayoutSettings decode(unsigned value) {
    return {(value & 1u) != 0, (value & 2u) != 0, (value & 4u) != 0};
  }
};

inline std::optional<CandidateLayoutSettings>
candidate_layout_settings(const nlohmann::json &preferences) {
  try {
    if (!preferences.is_object())
      return std::nullopt;
    const auto layout =
        preferences.value("candidate_layout", std::string("vertical"));
    const auto preedit =
        preferences.value("candidate_preedit_style", std::string("pinyin"));
    if ((layout != "horizontal" && layout != "vertical") ||
        (preedit != "pinyin" && preedit != "empty"))
      return std::nullopt;
    const auto hint = preferences.find("wubi_code_hint");
    if (hint != preferences.end() && !hint->is_boolean() && !hint->is_null())
      return std::nullopt;
    return CandidateLayoutSettings{layout == "horizontal", preedit != "empty",
                                   hint == preferences.end() || hint->is_null() || hint->get<bool>()};
  } catch (...) {
    return std::nullopt;
  }
}
} // namespace msime::windows

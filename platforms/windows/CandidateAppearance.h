#pragma once
#include <algorithm>
#include <filesystem>
#include <nlohmann/json.hpp>
#include <string>

namespace msime::windows {
// Translate the stored preferences into PreviewConfig's appearance block.
//
// Every field is optional on purpose. PreviewConfig validates hard - a colour
// over 32 bytes or a font size outside 8..48 throws - and that validation runs
// on the production launch path, so copying a bad stored value straight
// through would turn a cosmetic preference into a Server that refuses to
// start. A value that would not survive validation is left out instead, and
// the built-in default stands in for it.
//
// system_dark is resolved by the caller rather than read here, so this stays a
// pure function of its inputs and the registry is not consulted under test.
inline nlohmann::json candidate_appearance(const std::filesystem::path &state,
                                           const nlohmann::json &preferences,
                                           bool system_dark) {
  auto text = [&preferences](const char *name, const char *fallback) {
    return preferences.contains(name) && preferences.at(name).is_string()
               ? preferences.at(name).get<std::string>()
               : std::string(fallback);
  };
  nlohmann::json appearance{{"skin_directory", (state / "skins").u8string()}};
  const auto theme = text("theme", "dark");
  appearance["dark_theme"] =
      theme == "light" ? false : theme == "system" ? system_dark : true;
  appearance["layout"] =
      text("candidate_layout", "vertical") == "horizontal" ? "horizontal"
                                                           : "vertical";
  appearance["candidate_preedit_style"] =
      text("candidate_preedit_style", "pinyin") == "empty" ? "empty" : "pinyin";
  const auto skin = text("candidate_skin", "");
  if (!skin.empty() && skin.size() <= 64)
    appearance["skin"] = skin;
  // Mirrors PreviewConfig's own bounds, so anything kept here will load.
  auto printable = [](const std::string &value, size_t limit) {
    return !value.empty() && value.size() <= limit &&
           value.find('\0') == std::string::npos &&
           std::none_of(value.begin(), value.end(),
                        [](unsigned char c) { return c < 0x20; });
  };
  for (const char *name :
       {"candidate_font_size", "candidate_preedit_font_size"}) {
    if (!preferences.contains(name) ||
        !preferences.at(name).is_number_integer())
      continue;
    const auto size = preferences.at(name).get<int64_t>();
    if (size >= 8 && size <= 48)
      appearance[name] = static_cast<int>(size);
  }
  for (const char *name :
       {"candidate_text_color", "candidate_number_color",
        "candidate_surface_color", "candidate_border_color",
        "candidate_selected_color", "candidate_hover_color",
        "candidate_accent_color"}) {
    if (!preferences.contains(name) || !preferences.at(name).is_string())
      continue;
    const auto value = preferences.at(name).get<std::string>();
    if (printable(value, 32))
      appearance[name] = value;
  }
  const auto family = text("candidate_font_family", "");
  if (printable(family, 128))
    appearance["candidate_font"] = family;
  if (preferences.contains("candidate_fallback_fonts") &&
      preferences.at("candidate_fallback_fonts").is_array()) {
    auto fonts = nlohmann::json::array();
    for (const auto &font : preferences.at("candidate_fallback_fonts")) {
      if (fonts.size() >= 32 || !font.is_string())
        break;
      const auto value = font.get<std::string>();
      if (printable(value, 128))
        fonts.push_back(value);
    }
    if (!fonts.empty())
      appearance["candidate_fallback_fonts"] = fonts;
  }
  return appearance;
}
// The inline preedit the TSF side draws. PreviewConfig spells the pass-through
// case "local"; the stored preference spells the same thing "raw".
inline std::string tsf_preedit_style(const nlohmann::json &preferences) {
  if (!preferences.contains("tsf_preedit_style") ||
      !preferences.at("tsf_preedit_style").is_string())
    return "local";
  const auto style = preferences.at("tsf_preedit_style").get<std::string>();
  return style == "pinyin" || style == "empty" ? style : "local";
}
} // namespace msime::windows

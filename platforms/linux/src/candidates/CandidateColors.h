#pragma once

#include <cmath>
#include <cstdint>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "../core/CandidateSkinCatalog.h"
#include "CandidatePalette.h"

namespace msime::linux_host {

// The candidate colours both Linux frontends draw with, resolved from the shared preferences in one place: IBus turns them into text attributes and Fcitx5 into a classic UI theme, so the two cannot disagree about what a skin or a custom colour means.
struct CandidateColors {
  std::optional<std::uint32_t> text;
  std::optional<std::uint32_t> number;
  std::optional<std::uint32_t> accent;
  std::optional<std::uint32_t> background;
  std::optional<std::uint32_t> selected;
  std::optional<std::uint32_t> selected_text;
  std::optional<std::uint32_t> selected_number;
};

inline std::optional<std::uint32_t> palette_color(const nlohmann::json &value) {
  if (!value.is_string()) return std::nullopt;
  const auto hex = value.get<std::string>();
  if (hex.size() != 7 || hex.front() != '#') return std::nullopt;
  std::uint32_t color = 0;
  for (std::size_t index = 1; index < hex.size(); ++index) {
    const auto c = static_cast<unsigned char>(hex[index]);
    std::uint32_t digit;
    if (c >= '0' && c <= '9') digit = c - '0';
    else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
    else return std::nullopt;
    color = (color << 4) | digit;
  }
  return color;
}

inline std::optional<std::uint32_t> contrasting_color(std::optional<std::uint32_t> background) {
  if (!background) return std::nullopt;
  const auto linear = [](std::uint32_t channel) {
    const double value = channel / 255.0;
    return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
  };
  const auto luminance = 0.2126 * linear((*background >> 16) & 0xff) +
                         0.7152 * linear((*background >> 8) & 0xff) +
                         0.0722 * linear(*background & 0xff);
  const auto black_contrast = (luminance + 0.05) / 0.05;
  const auto white_contrast = 1.05 / (luminance + 0.05);
  return black_contrast >= white_contrast ? 0x000000u : 0xffffffu;
}

// Resolve "follow" against the system appearance and fill the colours an installed (external) skin supplies for that appearance. Colours the user set explicitly always win over the skin's.
inline nlohmann::json candidate_display_preferences(nlohmann::json preferences, bool system_dark,
                                                    const std::vector<CandidateSkin> &builtin_skins,
                                                    const std::string &default_skin,
                                                    const nlohmann::json &catalog) {
  using Json = nlohmann::json;
  if (preferences.value("candidate_theme", "follow") == "follow")
    preferences["candidate_theme"] = system_dark ? "dark" : "light";
  const auto selected = preferences.value("candidate_skin", default_skin);
  if (candidate_skin_title(builtin_skins, selected) != "外部：" + selected) return preferences;
  if (!catalog.is_object()) return preferences;
  const auto packages = catalog.find("packages");
  if (packages == catalog.end() || !packages->is_array()) return preferences;
  for (const auto &package : *packages) {
    if (!package.is_object() || package.value("id", std::string{}) != selected) continue;
    const auto candidate = package.value("candidate", Json::object());
    if (!candidate.is_object()) break;
    const auto theme = preferences.value("candidate_theme", "follow") == "dark" ? "dark" : "light";
    const auto palette = candidate.value(theme, Json::object());
    if (!palette.is_object()) break;
    if (!preferences.value("candidate_text_color", Json(nullptr)).is_string() && palette.contains("text"))
      preferences["candidate_text_color"] = palette["text"];
    if (!preferences.value("candidate_number_color", Json(nullptr)).is_string() && palette.contains("number"))
      preferences["candidate_number_color"] = palette["number"];
    if (!preferences.value("candidate_accent_color", Json(nullptr)).is_string() && palette.contains("accent"))
      preferences["candidate_accent_color"] = palette["accent"];
    if (!preferences.value("candidate_selected_color", Json(nullptr)).is_string() && palette.contains("selected"))
      preferences["candidate_selected_color"] = palette["selected"];
    const bool custom_surface = preferences.value("candidate_background_color", Json(nullptr)).is_string() ||
                                preferences.value("candidate_surface_color", Json(nullptr)).is_string();
    if (!custom_surface && palette.contains("surface"))
      preferences["candidate_background_color"] = palette["surface"];
    break;
  }
  return preferences;
}

// Takes preferences already passed through candidate_display_preferences.
inline CandidateColors resolve_candidate_colors(const nlohmann::json &preferences,
                                                const std::string &default_skin) {
  using Json = nlohmann::json;
  const auto custom = [&](const char *key) { return palette_color(preferences.value(key, Json(nullptr))); };
  const auto skin = preferences.value("candidate_skin", default_skin);
  const auto theme = preferences.value("candidate_theme", "follow");
  const bool dark = theme == "dark";
  const bool builtin = candidate_builtin_skin(skin);
  const auto palette = candidate_builtin_palette(skin, dark);
  CandidateColors colors;
  if (auto value = custom("candidate_background_color")) colors.background = value;
  else if (auto surface = custom("candidate_surface_color")) colors.background = surface;
  else if (builtin) colors.background = palette.surface;
  else if (theme == "dark") colors.background = 0x202124u;
  else if (theme == "light") colors.background = 0xffffffu;
  if (auto value = custom("candidate_text_color")) colors.text = value;
  else if (builtin) colors.text = palette.text;
  else colors.text = contrasting_color(colors.background);
  if (auto value = custom("candidate_number_color")) colors.number = value;
  else if (builtin) colors.number = palette.number;
  if (auto value = custom("candidate_accent_color")) colors.accent = value;
  else if (builtin) colors.accent = palette.accent;
  if (auto value = custom("candidate_selected_color")) colors.selected = value;
  else if (builtin) colors.selected = palette.selected;
  // A custom text colour applies to the selected row as well; otherwise the skin may give the selected row its own text colour.
  if (auto value = custom("candidate_text_color")) colors.selected_text = value;
  else if (builtin && palette.selected_text) colors.selected_text = palette.selected_text;
  else colors.selected_text = colors.text;
  if (auto value = custom("candidate_number_color")) colors.selected_number = value;
  else if (builtin && palette.selected_number) colors.selected_number = palette.selected_number;
  else colors.selected_number = colors.number;
  return colors;
}

}  // namespace msime::linux_host

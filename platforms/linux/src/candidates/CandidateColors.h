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
  // The card's outline, already composited over the background: Fcitx5's classic UI paints the border with the SOURCE operator, so a translucent one would show the desktop through the panel rather than tint the surface the way it does on Windows. Only Fcitx5 draws it; IBus text attributes have no way to outline the panel.
  std::optional<std::uint32_t> border;
  int border_width = 0;
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

struct CandidateBorderColor {
  std::uint32_t rgb = 0;
  std::uint8_t alpha = 0xFF;
};

// The border as a user preference (#rrggbb) or a skin package (#rrggbb, #rrggbbaa or transparent) writes it. Anything else, including the rgba() form a package may carry for its web card, is not understood here and keeps the skin's own border, as an unparsable value does on Windows.
inline std::optional<CandidateBorderColor> candidate_border_color(const nlohmann::json &value) {
  if (!value.is_string()) return std::nullopt;
  const auto text = value.get<std::string>();
  if (text == "transparent") return CandidateBorderColor{0, 0};
  if (text.size() == 7) {
    if (const auto rgb = palette_color(value)) return CandidateBorderColor{*rgb, 0xFF};
    return std::nullopt;
  }
  if (text.size() != 9) return std::nullopt;
  const auto rgb = palette_color(nlohmann::json(text.substr(0, 7)));
  const auto alpha = palette_color(nlohmann::json("#0000" + text.substr(7)));
  if (!rgb || !alpha) return std::nullopt;
  return CandidateBorderColor{*rgb, static_cast<std::uint8_t>(*alpha)};
}

// Source-over of one colour at the given alpha on an opaque background.
inline std::uint32_t composite_color(std::uint32_t color, std::uint8_t alpha, std::uint32_t background) {
  std::uint32_t result = 0;
  for (const int shift : {16, 8, 0}) {
    const auto top = (color >> shift) & 0xffu;
    const auto bottom = (background >> shift) & 0xffu;
    result |= ((top * alpha + bottom * (255u - alpha) + 127u) / 255u) << shift;
  }
  return result;
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

// Resolve "follow" against the global theme mode, as Windows resolves theme_cand against theme_mode and as the voice overlay does here (VoiceAction.h): the desktop appearance decides only when that mode is "system", which is also the shared default when the key is absent. Then fill the colours an installed (external) skin supplies for that appearance. Colours the user set explicitly always win over the skin's.
inline nlohmann::json candidate_display_preferences(nlohmann::json preferences, bool system_dark,
                                                    const std::vector<CandidateSkin> &builtin_skins,
                                                    const std::string &default_skin,
                                                    const nlohmann::json &catalog) {
  using Json = nlohmann::json;
  if (preferences.value("candidate_theme", "follow") == "follow") {
    const auto global = preferences.value("theme", "system");
    const bool dark = global == "system" ? system_dark : global != "light";
    preferences["candidate_theme"] = dark ? "dark" : "light";
  }
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
    if (!preferences.value("candidate_border_color", Json(nullptr)).is_string() && palette.contains("border"))
      preferences["candidate_border_color"] = palette["border"];
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
  // An installed skin is drawn on fluent's card on Windows, so it has fluent's outline unless it names its own colour, and a custom colour keeps the skin's width: willow_green draws no outline for any colour.
  auto border = CandidateBorderColor{palette.border, palette.border_alpha};
  if (auto value = candidate_border_color(preferences.value("candidate_border_color", Json(nullptr)))) border = *value;
  if (colors.background && palette.border_width > 0 && border.alpha > 0) {
    colors.border = composite_color(border.rgb, border.alpha, *colors.background);
    colors.border_width = palette.border_width;
  }
  return colors;
}

}  // namespace msime::linux_host

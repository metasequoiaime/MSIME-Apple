#pragma once
#include "CandidatePalette.h"
#include <nlohmann/json.hpp>
#include <string>

namespace msime::windows {
// Reads the catalog msime_client_skin_catalog returns and resolves one package
// into the presenter's tokens. The shared catalog already validated the
// manifest; nothing here trusts it further than the color parser does.
inline CandidatePaletteOverrides
candidate_skin_overrides(const nlohmann::json &catalog, const std::string &id,
                         bool dark, const std::string &layout) {
  CandidatePaletteOverrides overrides;
  if (id.empty() || !catalog.is_object() || !catalog.contains("packages") ||
      !catalog.at("packages").is_array())
    return overrides;
  const std::string theme = dark ? "dark" : "light";
  for (const auto &package : catalog.at("packages")) {
    if (!package.is_object() || !package.contains("id") ||
        !package.at("id").is_string() || package.at("id") != id)
      continue;
    // Compatibility comes from the manifest, so a package that never claimed
    // this layout or theme keeps the built-in tokens instead of half applying.
    auto claims = [&package](const char *key, const std::string &value) {
      if (!package.contains(key) || !package.at(key).is_array())
        return false;
      for (const auto &entry : package.at(key))
        if (entry.is_string() && entry.get<std::string>() == value)
          return true;
      return false;
    };
    if (!claims("layouts", layout) || !claims("themes", theme))
      return overrides;
    if (!package.contains("candidate") || !package.at("candidate").is_object())
      return overrides;
    const auto &colors = package.at("candidate");
    if (!colors.contains(theme) || !colors.at(theme).is_object())
      return overrides;
    const auto &palette = colors.at(theme);
    auto color = [&palette](const char *key) -> std::optional<std::string> {
      if (!palette.contains(key) || !palette.at(key).is_string())
        return std::nullopt;
      auto value = palette.at(key).get<std::string>();
      // The catalog bounds this already; refuse anything longer rather than
      // handing an unbounded string to the parser.
      if (value.empty() || value.size() > 80)
        return std::nullopt;
      return value;
    };
    overrides.accent = color("accent");
    overrides.selected = color("selected");
    overrides.hover = color("hover");
    overrides.surface = color("surface");
    overrides.border = color("border");
    overrides.text = color("text");
    overrides.number = color("number");
    if (palette.contains("showSelectedBar") &&
        palette.at("showSelectedBar").is_boolean())
      overrides.show_selected_bar = palette.at("showSelectedBar").get<bool>();
    return overrides;
  }
  return overrides;
}
// Built-in tokens for the theme, with the selected package applied on top.
inline CandidatePalette candidate_skin_palette(const nlohmann::json &catalog,
                                               const std::string &id, bool dark,
                                               const std::string &layout) {
  return candidate_palette(candidate_skin_overrides(catalog, id, dark, layout),
                           dark ? CandidatePalette{}
                                : candidate_light_palette());
}
} // namespace msime::windows

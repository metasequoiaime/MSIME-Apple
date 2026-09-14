#pragma once
#include <filesystem>
#include "CandidatePalette.h"
#include <nlohmann/json.hpp>
#include <string>

namespace msime::windows {
// Reads the catalog msime_client_skin_catalog returns and resolves one package
// into the presenter's tokens. The shared catalog already validated the
// manifest; nothing here trusts it further than the color parser does.
// The mascot a package draws above the card, if it has one.
//
// The catalog parses these and the settings preview renders them, but the live
// card never touched any of it - a mascot skin looked right in settings and
// plain while actually typing.
struct CandidateSkinDecoration {
  // Absolute path to the image, empty when the package has none.
  std::wstring image;
  // How far the artwork rises above the card's top edge, in DIPs.
  double top_dip = 0.0;
  // Drawn width in DIPs; the height follows the image's own aspect ratio.
  double width_dip = 0.0;
};
inline CandidateSkinDecoration
candidate_skin_decoration(const nlohmann::json &catalog, const std::string &id,
                          const std::filesystem::path &root) {
  CandidateSkinDecoration decoration;
  if (id.empty() || !catalog.is_object() || !catalog.contains("packages") ||
      !catalog.at("packages").is_array())
    return decoration;
  for (const auto &package : catalog.at("packages")) {
    if (!package.is_object() || !package.contains("id") ||
        !package.at("id").is_string() || package.at("id") != id)
      continue;
    if (!package.contains("preview") || !package.at("preview").is_string())
      return decoration;
    const auto preview = package.at("preview").get<std::string>();
    // The catalog already refused a preview that escapes the package
    // directory; refuse an empty or over-long one here rather than building a
    // path from it.
    if (preview.empty() || preview.size() > 256)
      return decoration;
    const auto top = package.value("decoration_top_dip", 0.0);
    const auto width = package.value("decoration_width_dip", 0.0);
    // Both are required: a decoration with no width would draw nothing, and
    // one that does not rise above the card is not a decoration.
    if (!(top > 0.0) || !(width > 0.0) || top > 512.0 || width > 1024.0)
      return decoration;
    auto path = root / std::filesystem::u8path(id) /
                std::filesystem::u8path(preview);
    std::error_code error;
    if (!std::filesystem::is_regular_file(path, error))
      return decoration;
    decoration.image = path.wstring();
    decoration.top_dip = top;
    decoration.width_dip = width;
    return decoration;
  }
  return decoration;
}
// The minimum card width a package asks for, in DIPs, or 0 when it asks for
// none. A mascot skin is drawn against a card of a particular width; a narrower
// card makes the decoration overhang it.
inline double candidate_skin_min_width(const nlohmann::json &catalog,
                                       const std::string &id) {
  if (id.empty() || !catalog.is_object() || !catalog.contains("packages") ||
      !catalog.at("packages").is_array())
    return 0.0;
  for (const auto &package : catalog.at("packages")) {
    if (!package.is_object() || !package.contains("id") ||
        !package.at("id").is_string() || package.at("id") != id)
      continue;
    if (!package.contains("min_width_dip") ||
        !package.at("min_width_dip").is_number())
      return 0.0;
    const auto value = package.at("min_width_dip").get<double>();
    // The catalog validates the manifest, but a value this card cannot use is
    // still refused here rather than propagated into the geometry.
    if (!(value > 0.0) || value > 2000.0)
      return 0.0;
    return value;
  }
  return 0.0;
}
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

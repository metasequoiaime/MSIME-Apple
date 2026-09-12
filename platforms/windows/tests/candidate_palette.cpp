#include "CandidatePalette.h"
#include <cmath>
#include <stdexcept>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Candidate palette validation failed");
}
bool same(CandidateColor color, float r, float g, float b, float a) {
  auto near = [](float value, float expected) {
    return std::fabs(value - expected) < 0.002f;
  };
  return near(color.r, r) && near(color.g, g) && near(color.b, b) &&
         near(color.a, a);
}
int main() {
  const CandidateColor fallback = candidate_rgb(0x112233, 0.5f);
  // Hex forms the manifests use, with and without alpha.
  require(same(parse_css_color("#ff8000", fallback), 1.0f, 128 / 255.0f, 0.0f,
               1.0f));
  require(same(parse_css_color("ff8000", fallback), 1.0f, 128 / 255.0f, 0.0f,
               1.0f));
  require(same(parse_css_color("#f80", fallback), 1.0f, 136 / 255.0f, 0.0f,
               1.0f));
  require(same(parse_css_color("#e9e8e89d", fallback), 233 / 255.0f,
               232 / 255.0f, 232 / 255.0f, 157 / 255.0f));
  require(same(parse_css_color("  #ff8000\t", fallback), 1.0f, 128 / 255.0f,
               0.0f, 1.0f));

  // Functional notation, including the optional alpha argument.
  require(same(parse_css_color("rgb(255, 128, 0)", fallback), 1.0f,
               128 / 255.0f, 0.0f, 1.0f));
  require(same(parse_css_color("rgba(255, 128, 0, 0.25)", fallback), 1.0f,
               128 / 255.0f, 0.0f, 0.25f));
  require(same(parse_css_color("rgb(255 128 0)", fallback), 1.0f, 128 / 255.0f,
               0.0f, 1.0f));

  // Keywords: transparent is a value, the rest defer to the caller's color.
  require(same(parse_css_color("transparent", fallback), 0.0f, 0.0f, 0.0f,
               0.0f));
  for (const char *keyword : {"auto", "none", "", "   "})
    require(parse_css_color(keyword, fallback) == fallback);

  // Anything this presenter cannot represent keeps the built-in color rather
  // than rendering an invisible or wrong candidate window.
  for (const char *unsupported :
       {"red", "#12345", "#gggggg", "hsl(10, 20%, 30%)", "rgb(255, 128)",
        "rgb(255 128 0", "var(--accent)", "#"})
    require(parse_css_color(unsupported, fallback) == fallback);

  // Defaults match the shipped dark tokens.
  const CandidatePalette defaults;
  require(same(defaults.surface, 32 / 255.0f, 32 / 255.0f, 32 / 255.0f, 1.0f));
  require(same(defaults.accent, 107 / 255.0f, 105 / 255.0f, 214 / 255.0f,
               1.0f));
  require(defaults.show_selected_bar && defaults.radius == 6.0f &&
          defaults.border_width == 1.5f && defaults.item_radius == 4.0f);

  // A package overrides only what it declares.
  CandidatePaletteOverrides overrides;
  overrides.accent = "#00ff00";
  overrides.show_selected_bar = false;
  const auto skinned = candidate_palette(overrides);
  require(same(skinned.accent, 0.0f, 1.0f, 0.0f, 1.0f));
  require(!skinned.show_selected_bar);
  require(skinned.surface == defaults.surface &&
          skinned.selected == defaults.selected);

  // Empty and unparsable declarations fall back to the value being replaced.
  CandidatePaletteOverrides blank;
  blank.surface = "";
  blank.text = "definitely not a color";
  const auto unchanged = candidate_palette(blank);
  require(unchanged.surface == defaults.surface &&
          unchanged.text == defaults.text);

  // Overrides compose onto a caller-supplied base, so a light theme can start
  // from its own tokens.
  CandidatePalette light;
  light.surface = candidate_rgb(0xFFFFFF);
  light.text = candidate_rgb(0x1A1A1A);
  CandidatePaletteOverrides tint;
  tint.border = "rgba(0, 0, 0, 0.1)";
  const auto themed = candidate_palette(tint, light);
  require(themed.surface == light.surface && themed.text == light.text);
  require(same(themed.border, 0.0f, 0.0f, 0.0f, 0.1f));
}

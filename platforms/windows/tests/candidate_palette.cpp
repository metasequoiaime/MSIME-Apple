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

  // The light branch replaces only the colors the shipped presenter overrides.
  const auto light_defaults = candidate_light_palette();
  require(same(light_defaults.surface, 1.0f, 1.0f, 1.0f, 1.0f));
  require(same(light_defaults.border, 0.0f, 0.0f, 0.0f, 0.12f));
  require(same(light_defaults.number, 26 / 255.0f, 26 / 255.0f, 26 / 255.0f,
               0.55f));
  require(light_defaults.accent == defaults.accent &&
          light_defaults.radius == defaults.radius &&
          light_defaults.show_selected_bar == defaults.show_selected_bar);

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

  // The four shipped ids are resolved from the built-in table, never from a
  // package on disk: the shared catalog refuses to load one under these names.
  require(candidate_builtin_skin("fluent") &&
          candidate_builtin_skin("wechat") &&
          candidate_builtin_skin("graphite") &&
          candidate_builtin_skin("willow_green"));
  require(!candidate_builtin_skin("") && !candidate_builtin_skin("nord") &&
          !candidate_builtin_skin("Fluent"));

  // fluent is the baseline, so it must come back byte-for-byte as the defaults.
  const auto fluent_dark = candidate_builtin_palette("fluent", true);
  require(fluent_dark.surface == defaults.surface &&
          fluent_dark.selected == defaults.selected &&
          fluent_dark.show_selected_bar && fluent_dark.radius == 6.0f);
  require(candidate_builtin_palette("fluent", false).surface ==
          candidate_light_palette().surface);
  // An unknown id keeps fluent rather than rendering something invented.
  require(candidate_builtin_palette("nord", true).surface == defaults.surface);

  // Each shipped skin has to be visibly its own, not a relabelled fluent -
  // that identity was the whole defect. Values mirror the shipped presenter.
  for (const bool dark : {false, true}) {
    const auto wechat = candidate_builtin_palette("wechat", dark);
    require(same(wechat.selected, 0x07 / 255.0f, 0xC1 / 255.0f, 0x60 / 255.0f, 1.0f));
    require(wechat.accent == wechat.selected);
    require(!wechat.show_selected_bar);
    require(wechat.radius == 5.0f && wechat.border_width == 1.0f &&
            wechat.container_padding == 2.0f);
    // Opaque green fill, so the selected row needs its own white text.
    require(same(wechat.selected_text, 1.0f, 1.0f, 1.0f, 1.0f));
    require(same(wechat.selected_number, 1.0f, 1.0f, 1.0f, 1.0f));
    require(wechat.surface != defaults.surface);

    const auto willow = candidate_builtin_palette("willow_green", dark);
    require(willow.radius == 9.0f && willow.border_width == 0.0f &&
            willow.container_padding == 0.0f);
    // Deliberate divergence from the CSS, which uses 0 plus a clip-path.
    require(willow.item_radius == 4.0f);
    require(willow.border.a == 0.0f); // Borderless card.
    require(same(willow.selected_text, 1.0f, 1.0f, 1.0f, 1.0f));
    require(!willow.show_selected_bar);

    const auto graphite = candidate_builtin_palette("graphite", dark);
    require(graphite.radius == 3.0f && graphite.item_radius == 2.0f &&
            graphite.container_padding == 5.0f);
    // Graphite marks selection by text colour alone; the fill is transparent.
    require(graphite.selected.a == 0.0f);
    require(!graphite.show_selected_bar);
    // So a selected colour is mandatory here, or the row would not change.
    require(graphite.selected_text.a > 0.0f &&
            graphite.selected_number.a > 0.0f);
    require(graphite.selected_text != graphite.text);
  }
  // Light and dark are genuinely different tokens, not one table reused.
  require(candidate_builtin_palette("graphite", true).surface !=
          candidate_builtin_palette("graphite", false).surface);
  require(candidate_builtin_palette("willow_green", true).accent !=
          candidate_builtin_palette("willow_green", false).accent);
  // fluent names no selected colour, so rows keep their normal one.
  require(fluent_dark.selected_text.a == 0.0f &&
          fluent_dark.selected_number.a == 0.0f);

  // The toolbar follows the same skin but resolves light/dark from its own
  // preference, and the shipped default skin uses a lighter accent than the
  // card - the drag handle and hover tint are drawn from it.
  require(same(toolbar_palette("fluent", true).accent, 0x8E / 255.0f,
               0x8C / 255.0f, 0xD8 / 255.0f, 1.0f));
  require(toolbar_palette("fluent", true).accent != defaults.accent);
  require(same(toolbar_palette("", true).accent, 0x8E / 255.0f, 0x8C / 255.0f,
               0xD8 / 255.0f, 1.0f));
  // An external skin id is not a built-in, so it keeps the default accent too.
  require(toolbar_palette("nord", true).accent ==
          toolbar_palette("fluent", true).accent);
  // Every shipped skin keeps its own accent, which is what makes the toolbar
  // look like the card the user chose.
  for (const bool dark : {false, true}) {
    require(toolbar_palette("wechat", dark).accent ==
            candidate_builtin_palette("wechat", dark).accent);
    require(toolbar_palette("graphite", dark).accent ==
            candidate_builtin_palette("graphite", dark).accent);
    require(toolbar_palette("willow_green", dark).accent ==
            candidate_builtin_palette("willow_green", dark).accent);
  }
  // Light and dark remain distinct surfaces.
  require(toolbar_palette("wechat", true).surface !=
          toolbar_palette("wechat", false).surface);
}

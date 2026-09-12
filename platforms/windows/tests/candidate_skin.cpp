#include "CandidateSkin.h"
#include <cmath>
#include <stdexcept>

using namespace msime::windows;
using Json = nlohmann::json;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Candidate skin validation failed");
}
bool same(CandidateColor color, float r, float g, float b, float a) {
  auto near = [](float value, float expected) {
    return std::fabs(value - expected) < 0.002f;
  };
  return near(color.r, r) && near(color.g, g) && near(color.b, b) &&
         near(color.a, a);
}
Json package(const char *id, Json layouts, Json themes) {
  return Json{{"id", id},
              {"name", "Sample"},
              {"version", "1.0"},
              {"base", "fluent"},
              {"layouts", std::move(layouts)},
              {"themes", std::move(themes)},
              {"minWidthDip", 10.0},
              {"candidate",
               {{"dark",
                 {{"surface", "#101010"},
                  {"text", "#fafafa"},
                  {"accent", "rgb(7, 193, 96)"},
                  {"showSelectedBar", false}}},
                {"light", {{"surface", "#f7f7f7"}, {"text", "#333333"}}}}}};
}
int main() {
  const Json catalog{
      {"packages",
       Json::array({package("wechat", Json::array({"vertical", "horizontal"}),
                            Json::array({"dark", "light"})),
                    package("partial", Json::array({"vertical"}),
                            Json::array({"light"}))})},
      {"issues", Json::array()}};

  // A package that claims the layout and theme replaces only its own tokens.
  const auto dark = candidate_skin_palette(catalog, "wechat", true, "vertical");
  require(same(dark.surface, 16 / 255.0f, 16 / 255.0f, 16 / 255.0f, 1.0f));
  require(same(dark.text, 250 / 255.0f, 250 / 255.0f, 250 / 255.0f, 1.0f));
  require(same(dark.accent, 7 / 255.0f, 193 / 255.0f, 96 / 255.0f, 1.0f));
  require(!dark.show_selected_bar);
  require(dark.selected == CandidatePalette{}.selected);
  const auto light = candidate_skin_palette(catalog, "wechat", false, "vertical");
  require(same(light.surface, 247 / 255.0f, 247 / 255.0f, 247 / 255.0f, 1.0f));
  require(light.show_selected_bar); // The light palette never declared it.

  // Compatibility comes from the manifest: an unclaimed layout or theme keeps
  // the built-ins rather than applying half a skin.
  const auto unsupported =
      candidate_skin_palette(catalog, "partial", true, "vertical");
  require(unsupported.surface == CandidatePalette{}.surface &&
          unsupported.text == CandidatePalette{}.text);
  require(candidate_skin_palette(catalog, "partial", false, "horizontal")
              .surface == candidate_light_palette().surface);
  require(candidate_skin_palette(catalog, "partial", false, "vertical")
              .surface != candidate_light_palette().surface);

  // Unknown, unnamed and malformed catalogs fall back to the built-in tokens.
  for (const auto &missing :
       {candidate_skin_overrides(catalog, "absent", true, "vertical"),
        candidate_skin_overrides(catalog, "", true, "vertical"),
        candidate_skin_overrides(Json::object(), "wechat", true, "vertical"),
        candidate_skin_overrides(Json{{"packages", 7}}, "wechat", true,
                                 "vertical"),
        candidate_skin_overrides(Json::array(), "wechat", true, "vertical")})
    require(!missing.surface && !missing.text && !missing.show_selected_bar);

  // Entries that are not strings, are empty or exceed the catalog's own bound
  // are dropped instead of reaching the color parser.
  Json hostile = catalog;
  hostile["packages"][0]["candidate"]["dark"]["surface"] = 42;
  hostile["packages"][0]["candidate"]["dark"]["text"] = "";
  hostile["packages"][0]["candidate"]["dark"]["accent"] = std::string(81, 'a');
  hostile["packages"][0]["candidate"]["dark"]["showSelectedBar"] = "yes";
  const auto guarded =
      candidate_skin_overrides(hostile, "wechat", true, "vertical");
  require(!guarded.surface && !guarded.text && !guarded.accent &&
          !guarded.show_selected_bar);
  const auto fallback =
      candidate_skin_palette(hostile, "wechat", true, "vertical");
  require(fallback.surface == CandidatePalette{}.surface &&
          fallback.show_selected_bar);
}

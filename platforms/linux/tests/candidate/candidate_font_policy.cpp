#include "../src/candidates/CandidateFontPolicy.h"

#include <cassert>

int main() {
  using msime::linux_host::candidate_pango_font;
  using msime::linux_host::CandidateFont;
  using msime::linux_host::CandidateFontSync;

  assert(candidate_pango_font({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 18}) ==
         "Noto Sans SC, Microsoft YaHei, 18px");
  // Blank entries and repeats are dropped, surrounding space is trimmed.
  assert(candidate_pango_font({"  LXGW WenKai ", {"", "LXGW WenKai", "Noto Sans CJK SC"}, 20}) ==
         "LXGW WenKai, Noto Sans CJK SC, 20px");
  // A trailing style word stays part of the family because the list ends with a comma.
  assert(candidate_pango_font({"Source Han Sans Bold", {}, 16}) == "Source Han Sans Bold, 16px");
  // A comma inside a name cannot split it into two families.
  assert(candidate_pango_font({"Odd,Name", {}, 16}) == "OddName, 16px");
  // Out-of-range sizes fall back to the shared default rather than reaching the panel.
  assert(candidate_pango_font({"Sans", {}, 4}) == "Sans, 18px");
  assert(candidate_pango_font({"", {}, 14}) == "14px");

  using msime::linux_host::read_candidate_font;
  // A document without the keys reads as the store's defaults.
  assert(candidate_pango_font(read_candidate_font(nlohmann::json::object())) ==
         "Noto Sans SC, Microsoft YaHei, 18px");
  assert(candidate_pango_font(read_candidate_font(nlohmann::json{
             {"candidate_font_family", "LXGW WenKai"},
             {"candidate_fallback_fonts", nlohmann::json::array({"Noto Sans CJK SC", 3})},
             {"candidate_font_size", 24}})) == "LXGW WenKai, Noto Sans CJK SC, 24px");
  // An emptied fallback list stays empty rather than reverting to the defaults.
  assert(candidate_pango_font(read_candidate_font(nlohmann::json{
             {"candidate_fallback_fonts", nlohmann::json::array()}})) == "Noto Sans SC, 18px");

  // The English family leads the list, as Windows draws Latin from it first; the primary family and the fallbacks follow for the glyphs it lacks, without repeats.
  assert(candidate_pango_font(read_candidate_font(nlohmann::json{
             {"candidate_english_font", "Inter"}})) == "Inter, Noto Sans SC, Microsoft YaHei, 18px");
  assert(candidate_pango_font(read_candidate_font(nlohmann::json{
             {"candidate_english_font", " Microsoft YaHei "},
             {"candidate_font_family", "LXGW WenKai"}})) ==
         "Microsoft YaHei, LXGW WenKai, Noto Sans SC, 18px");
  assert(candidate_pango_font({"Noto Sans SC", {"Noto Sans SC"}, 18, "Noto Sans SC"}) == "Noto Sans SC, 18px");
  // Unset (absent, null or blank) leaves the description exactly as it was before the setting existed.
  assert(candidate_pango_font(read_candidate_font(nlohmann::json{
             {"candidate_english_font", nullptr}})) == "Noto Sans SC, Microsoft YaHei, 18px");
  assert(candidate_pango_font({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 18, "  "}) ==
         "Noto Sans SC, Microsoft YaHei, 18px");

  using msime::linux_host::candidate_font_is_default;
  assert(candidate_font_is_default(read_candidate_font(nlohmann::json::object())));
  assert(candidate_font_is_default(read_candidate_font(nlohmann::json{{"candidate_english_font", nullptr}})));
  assert(!candidate_font_is_default(read_candidate_font(nlohmann::json{{"candidate_english_font", "Inter"}})));

  CandidateFontSync untouched;
  assert(!untouched.next({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 18}));
  assert(!untouched.next({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 18}));
  assert(untouched.next({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 22}) ==
         "Noto Sans SC, Microsoft YaHei, 22px");
  // Going back to the defaults after a change is itself a change the panel must see.
  assert(untouched.next({"Noto Sans SC", {"Noto Sans SC", "Microsoft YaHei"}, 18}) ==
         "Noto Sans SC, Microsoft YaHei, 18px");

  CandidateFontSync chosen;
  assert(chosen.next({"LXGW WenKai", {}, 20}) == "LXGW WenKai, 20px");
  assert(!chosen.next({"LXGW WenKai", {}, 20}));

  // Choosing only an English family is a font choice the panel must see, even on the first refresh.
  CandidateFontSync english;
  assert(english.next(read_candidate_font(nlohmann::json{{"candidate_english_font", "Inter"}})) ==
         "Inter, Noto Sans SC, Microsoft YaHei, 18px");
  assert(!english.next(read_candidate_font(nlohmann::json{{"candidate_english_font", "Inter"}})));
  return 0;
}

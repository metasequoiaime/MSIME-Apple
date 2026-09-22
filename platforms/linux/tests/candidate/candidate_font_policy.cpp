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
  return 0;
}

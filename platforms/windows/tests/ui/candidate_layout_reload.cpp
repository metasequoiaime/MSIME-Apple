#include "../../src/candidate/CandidateCardSize.h"
#include "../../src/candidate/CandidateLayoutSettings.h"
#include <cassert>

int main() {
  using namespace msime::windows;
  const auto defaults = candidate_layout_settings(nlohmann::json::object());
  assert(defaults && !defaults->horizontal && defaults->show_preedit);
  for (bool horizontal : {false, true}) {
    for (bool preedit : {false, true}) {
      auto settings = candidate_layout_settings(
          {{"candidate_layout", horizontal ? "horizontal" : "vertical"},
           {"candidate_preedit_style", preedit ? "pinyin" : "empty"}});
      assert(settings);
      auto decoded = CandidateLayoutSettings::decode(settings->encode());
      assert(decoded.horizontal == horizontal &&
             decoded.show_preedit == preedit);
    }
  }
  for (auto invalid : {nlohmann::json{{"candidate_layout", "diagonal"}},
                       nlohmann::json{{"candidate_layout", 2}},
                       nlohmann::json{{"candidate_preedit_style", "raw"}},
                       nlohmann::json{{"candidate_preedit_style", nullptr}},
                       nlohmann::json::array()})
    assert(!candidate_layout_settings(invalid));
  CandidateCardInput input;
  input.item_widths = {90, 90, 90};
  input.max_width = 1000;
  input.max_height = 1000;
  input.preedit_visible = true;
  input.horizontal = false;
  const auto vertical = candidate_card_size(input);
  input.horizontal = true;
  const auto horizontal = candidate_card_size(input);
  assert(horizontal.width > vertical.width);
  assert(horizontal.height < vertical.height);
  input.preedit_visible = false;
  const auto hidden_preedit = candidate_card_size(input);
  assert(hidden_preedit.height < horizontal.height);
}

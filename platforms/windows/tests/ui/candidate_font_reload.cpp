#include "../src/candidate/CandidateFontSettings.h"
#include <cassert>
#include <thread>

int main() {
  using namespace msime::windows;
  auto defaults = candidate_font_settings(nlohmann::json::object());
  assert(defaults && defaults->family == "Segoe UI" && defaults->size == 18 &&
         defaults->preedit_size == 15 && defaults->fallback.size() == 2);
  auto configured = candidate_font_settings(
      {{"candidate_english_font", "Synthetic Latin"},
       {"candidate_fallback_fonts", {"CJK A", "Emoji B"}},
       {"candidate_font_size", 24},
       {"candidate_preedit_font_size", 20}});
  assert(configured && configured->family == "Synthetic Latin" &&
         configured->fallback[0] == "CJK A" && configured->size == 24 &&
         configured->preedit_size == 20);
  auto empty = candidate_font_settings(
      {{"candidate_fallback_fonts", nlohmann::json::array()}});
  assert(empty && empty->fallback.empty());
  for (const auto &invalid :
       {nlohmann::json{{"candidate_english_font", ""}},
        nlohmann::json{{"candidate_english_font", "bad\nname"}},
        nlohmann::json{{"candidate_english_font", "bad\tname"}},
        nlohmann::json{{"candidate_english_font", std::string(129, 'x')}},
        nlohmann::json{{"candidate_english_font", 42}},
        nlohmann::json{{"candidate_font_size", -1}},
        nlohmann::json{{"candidate_font_size", 18.5}},
        nlohmann::json{{"candidate_preedit_font_size", 33}},
        nlohmann::json{{"candidate_fallback_fonts", {""}}},
        nlohmann::json{
            {"candidate_fallback_fonts", std::vector<std::string>(33, "A")}}})
    assert(!candidate_font_settings(invalid));

  CandidateFontMailbox mailbox;
  assert(!mailbox.take());
  assert(mailbox.publish(0, *defaults));
  assert(mailbox.publish(2, *configured));
  assert(!mailbox.publish(1, *defaults));
  assert(!mailbox.publish(2, *defaults));
  assert(mailbox.take() == configured);
  assert(!mailbox.take());
  auto invalid = *defaults;
  invalid.size = 99;
  assert(!mailbox.publish(100, invalid));
  assert(mailbox.publish(3, *empty));
  assert(mailbox.take() == empty);
  // Two writers can arrive out of order; only the largest revision survives.
  std::thread a([&] {
    for (uint64_t i = 4; i < 1000; i += 2)
      mailbox.publish(i, *defaults);
  });
  std::thread b([&] {
    for (uint64_t i = 5; i <= 1001; i += 2)
      mailbox.publish(i, *configured);
  });
  a.join();
  b.join();
  assert(mailbox.take() == configured);
  assert(!mailbox.publish(1000, *defaults));
}

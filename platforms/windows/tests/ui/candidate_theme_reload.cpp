#include "../src/candidate/CandidateAppearance.h"
#include <cassert>

int main() {
  using namespace msime::windows;
  for (bool system_dark : {false, true}) {
    for (const char *global : {"dark", "light", "system"}) {
      for (const char *surface : {"follow", "dark", "light"}) {
        const nlohmann::json values{{"theme", global},
                                    {"candidate_theme", surface}};
        const bool expected =
            std::string(surface) == "dark" ||
            (std::string(surface) == "follow" &&
             (std::string(global) == "dark" ||
              (std::string(global) == "system" && system_dark)));
        assert(candidate_theme_dark(values, system_dark) == expected);
        assert(candidate_appearance("state", values, system_dark)
                   .at("dark_theme") == expected);
      }
    }
  }
  const auto base = candidate_builtin_palette("wechat", false);
  nlohmann::json overrides;
  for (const char *key : {"candidate_text_color", "candidate_number_color",
                          "candidate_surface_color", "candidate_border_color",
                          "candidate_selected_color", "candidate_hover_color",
                          "candidate_accent_color"})
    overrides[key] = "#123456";
  auto changed = candidate_theme_palette(base, overrides);
  const auto color = candidate_rgb(0x123456);
  assert(changed.text == color && changed.number == color &&
         changed.surface == color && changed.border == color &&
         changed.selected == color && changed.hover == color &&
         changed.accent == color);
  assert(changed.radius == base.radius &&
         changed.selected_text == base.selected_text);
  // Clearing custom values resolves from the skin again, not the previous
  // override.
  auto reset = candidate_theme_palette(
      base, candidate_theme_values({{"candidate_text_color", nullptr},
                                    {"candidate_surface_color", "auto"}}));
  assert(reset.text == base.text && reset.surface == base.surface);
  assert(candidate_theme_palette(base, {{"candidate_text_color", "invalid"}})
             .text == base.text);
  CandidateThemeMailbox mailbox;
  assert(!mailbox.take());
  mailbox.publish(overrides);
  mailbox.publish({{"candidate_theme", "light"},
                   {"unrelated", "synthetic"},
                   {"candidate_text_color", std::string(100, 'x')}});
  const auto latest = mailbox.take();
  assert(latest && latest->size() == 1 &&
         latest->at("candidate_theme") == "light");
  assert(!mailbox.take());
}

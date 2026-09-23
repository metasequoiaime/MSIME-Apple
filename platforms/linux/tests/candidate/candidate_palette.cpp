#include "../src/candidates/CandidateColors.h"
#include "../src/candidates/CandidatePalette.h"

#include <cassert>

int main() {
  using msime::linux_host::candidate_builtin_accent;
  using msime::linux_host::candidate_builtin_palette;
  using msime::linux_host::candidate_builtin_skin;
  assert(candidate_builtin_accent("fluent", false) == 0x6B69D6u);
  assert(candidate_builtin_accent("fluent", true) == 0x6B69D6u);
  assert(candidate_builtin_accent("wechat", false) == 0x07C160u);
  assert(candidate_builtin_accent("graphite", false) == 0x5F6B7Au);
  assert(candidate_builtin_accent("graphite", true) == 0x8993A0u);
  assert(candidate_builtin_accent("willow_green", false) == 0x58B980u);
  assert(candidate_builtin_accent("willow_green", true) == 0x65C98Du);
  assert(candidate_builtin_accent("unknown", false) == 0x6B69D6u);

  assert(candidate_builtin_skin("fluent"));
  assert(candidate_builtin_skin("wechat"));
  assert(candidate_builtin_skin("graphite"));
  assert(candidate_builtin_skin("willow_green"));
  assert(!candidate_builtin_skin("unknown"));

  const auto fluent_dark = candidate_builtin_palette("fluent", true);
  assert(fluent_dark.surface == 0x202020u);
  assert(fluent_dark.text == 0xE9E8E8u);
  assert(fluent_dark.number == 0xE9E8E8u);
  assert(fluent_dark.selected == 0x3E3E3Eu);
  assert(!fluent_dark.selected_text && !fluent_dark.selected_number);

  const auto fluent_light = candidate_builtin_palette("fluent", false);
  assert(fluent_light.surface == 0xFFFFFFu);
  assert(fluent_light.text == 0x1A1A1Au);
  assert(fluent_light.selected == 0xE8E8E8u);

  for (const bool dark : {false, true}) {
    const auto wechat = candidate_builtin_palette("wechat", dark);
    assert(wechat.surface == (dark ? 0x151515u : 0xF7F7F7u));
    assert(wechat.accent == 0x07C160u && wechat.selected == 0x07C160u);
    assert(wechat.selected_text == 0xFFFFFFu);
    assert(wechat.selected_number == 0xFFFFFFu);

    const auto graphite = candidate_builtin_palette("graphite", dark);
    assert(graphite.surface == (dark ? 0x1C1F23u : 0xFBFBFCu));
    assert(!graphite.selected);
    assert(graphite.selected_text.has_value());
    assert(graphite.selected_number == graphite.selected_text);

    const auto willow = candidate_builtin_palette("willow_green", dark);
    assert(willow.surface == (dark ? 0x2D2F2Eu : 0xF4F5F3u));
    assert(willow.accent == willow.selected);
    assert(willow.selected_text == 0xFFFFFFu);
    assert(willow.selected_number == 0xFFFFFFu);

    // Outlines follow the Windows skin tokens; widths are whole pixels.
    assert(wechat.border == (dark ? 0x292929u : 0xDEDEDEu));
    assert(wechat.border_alpha == 0xFF && wechat.border_width == 1);
    assert(graphite.border == (dark ? 0x30353Bu : 0xE2E5E9u));
    assert(graphite.border_alpha == 0xFF && graphite.border_width == 1);
    assert(willow.border_width == 0 && willow.border_alpha == 0);
  }
  assert(fluent_light.border == 0x000000u && fluent_light.border_alpha == 0x1F && fluent_light.border_width == 1);
  assert(fluent_dark.border == 0x9B9B9Bu && fluent_dark.border_alpha == 0x2E && fluent_dark.border_width == 1);
  // An unknown id falls back to fluent, outline included.
  assert(candidate_builtin_palette("unknown", true).border == 0x9B9B9Bu);

  // "follow" takes the global theme mode, as Windows resolves theme_cand against theme_mode: only "system" consults the desktop appearance.
  {
    using Json = nlohmann::json;
    const std::vector<msime::linux_host::CandidateSkin> builtin = {{"fluent", "Fluent"}, {"wechat", "微信绿"}};
    const auto follow = [&](const char *global, bool system_dark) {
      return msime::linux_host::candidate_display_preferences(
                 Json{{"theme", global}, {"candidate_theme", "follow"}, {"candidate_skin", "wechat"}}, system_dark,
                 builtin, "fluent", Json())
          .value("candidate_theme", std::string{});
    };
    assert(follow("dark", false) == "dark");
    assert(follow("light", true) == "light");
    assert(follow("system", true) == "dark");
    assert(follow("system", false) == "light");
    // An explicit candidate theme still wins over both.
    const auto explicit_light = msime::linux_host::candidate_display_preferences(
        Json{{"theme", "dark"}, {"candidate_theme", "light"}}, true, builtin, "fluent", Json());
    assert(explicit_light.value("candidate_theme", std::string{}) == "light");
    // The resolved appearance reaches the colours: a dark global theme on a light desktop draws the dark skin.
    const auto colors = msime::linux_host::resolve_candidate_colors(
        msime::linux_host::candidate_display_preferences(
            Json{{"theme", "dark"}, {"candidate_theme", "follow"}, {"candidate_skin", "wechat"}}, false, builtin,
            "fluent", Json()),
        "fluent");
    assert(colors.background == 0x151515u);
  }

  assert(msime::linux_host::candidate_preedit_with_caret("nihao", "nihao", 0) ==
         "|nihao");
  assert(msime::linux_host::candidate_preedit_with_caret("nihao", "nihao", 2) ==
         "ni|hao");
  assert(msime::linux_host::candidate_preedit_with_caret("nihao", "nihao", 5) ==
         "nihao|");
  assert(msime::linux_host::candidate_preedit_with_caret("ni'hao", "nihao", 2) ==
         "ni'hao");
  assert(msime::linux_host::candidate_preedit_with_caret("nihao", "nihao", 9) ==
         "nihao");
}

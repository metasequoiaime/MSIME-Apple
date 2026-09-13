#include "CandidatePalette.h"

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
  }
}

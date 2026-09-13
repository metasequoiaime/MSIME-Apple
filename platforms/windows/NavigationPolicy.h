#pragma once
#include "ReplyCodec.h"
#include "msime_client.h"
#include <nlohmann/json.hpp>
#include <optional>

namespace msime::windows {
// Explicit snapshot supplied by the native dispatch owner. No implicit product
// defaults or preference persistence here. Only call after TSF context policy
// has excluded punctuation/word-to-character shortcuts.
struct NavigationBindings {
  bool minus_equal = false;
  bool comma_period = false;
  bool brackets = false;
  bool tab = false;
  bool page_up_down = false;
  bool arrows = false;
  bool mouse_wheel = false;
};
struct NavigationAction {
  std::optional<uint32_t> command;
  NavigationReply reply;
};
// Decode once per publication; no file reads or JSON parsing on the key path.
inline NavigationBindings
preference_navigation(const nlohmann::json &preferences) {
  if (!preferences.contains("navigation"))
    return {true, true, false, true, true, true, false};
  const auto &value = preferences.at("navigation");
  return {value.at("minus_equal").get<bool>(),
          value.at("comma_period").get<bool>(),
          value.at("brackets").get<bool>(),
          value.at("tab").get<bool>(),
          value.at("page_up_down").get<bool>(),
          value.at("arrows").get<bool>(),
          value.value("mouse_wheel", false)};
}
inline std::optional<NavigationAction>
navigation_action(const FanyImeNamedpipeData &packet,
                  const NavigationBindings &bindings, bool unicode) {
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  if (packet.event_type != FanyImePipeEventType::KeyEvent || (modifiers & ~1u))
    return std::nullopt;
  const auto key = packet.keycode;
  // Unicode '+' extends the code sequence, even with equal-key paging enabled.
  if (unicode && packet.wch == '+')
    return std::nullopt;
  bool previous;
  if ((bindings.minus_equal && (key == 0xBD || key == 0xBB)) ||
      (bindings.comma_period && (key == 0xBC || key == 0xBE)) ||
      (bindings.brackets && (key == 0xDB || key == 0xDD)) ||
      (bindings.page_up_down && (key == 0x21 || key == 0x22)))
    previous = key == 0xBD || key == 0xBC || key == 0xDB || key == 0x21;
  else if (bindings.tab && key == 0x09)
    previous = (modifiers & 1u) != 0;
  else if (bindings.arrows && (key == 0x26 || key == 0x28))
    return NavigationAction{key == 0x26 ? MSIME_PREVIOUS_CANDIDATE
                                        : MSIME_NEXT_CANDIDATE,
                            key == 0x26 ? NavigationReply::PreviousCandidate
                                        : NavigationReply::NextCandidate};
  else {
    switch (key) {
    case 0xBD:
    case 0xBB:
    case 0xBC:
    case 0xBE:
    case 0xDB:
    case 0xDD:
    case 0x09:
    case 0x21:
    case 0x22:
    case 0x26:
    case 0x28:
      // TSF already consumed this navigation request. Disabled is a reply,
      // not permission to reinterpret the key as text or another command.
      return NavigationAction{std::nullopt, NavigationReply::Ignored};
    default:
      return std::nullopt;
    }
  }
  return NavigationAction{previous ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE,
                          previous ? NavigationReply::PreviousPage
                                   : NavigationReply::NextPage};
}
} // namespace msime::windows

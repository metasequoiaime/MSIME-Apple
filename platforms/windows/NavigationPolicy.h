#pragma once
#include "ReplyCodec.h"
#include "msime_client.h"
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
};
struct NavigationAction {
  uint32_t command;
  NavigationReply reply;
};
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
  else
    return std::nullopt;
  return NavigationAction{previous ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE,
                          previous ? NavigationReply::PreviousPage
                                   : NavigationReply::NextPage};
}
} // namespace msime::windows

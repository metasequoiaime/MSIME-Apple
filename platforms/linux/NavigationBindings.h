#pragma once
#include "msime_client.h"
#include <ibus.h>
#include <nlohmann/json.hpp>
#include <optional>

namespace msime::linux_host {
// Windows' touch keyboard sends these private-use keyvals for candidate page
// navigation. Keep the values at the host boundary; ordinary IBus navigation
// bindings remain configurable below.
inline constexpr guint kTouchKeyboardNextPage = 0xf003;
inline constexpr guint kTouchKeyboardPreviousPage = 0xf004;

inline std::optional<uint32_t> touch_keyboard_command(guint key) {
  if (key == kTouchKeyboardNextPage)
    return MSIME_NEXT_PAGE;
  if (key == kTouchKeyboardPreviousPage)
    return MSIME_PREVIOUS_PAGE;
  return std::nullopt;
}

// Accept the Windows compatibility name for arrow navigation while keeping
// the shared navigation schema canonical.
// Host key bindings only. Candidate movement and paging belong to the shared
// runtime. IBus key values describe the active keyboard layout, not Windows
// VKs.
struct NavigationBindings {
  bool minus_equal = true;
  bool comma_period = true;
  bool brackets = false;
  bool tab = true;
  bool page_up_down = true;
  bool mouse_wheel = false;
  bool arrows = true;

  static NavigationBindings read(const nlohmann::json &preferences) {
    if (!preferences.contains("navigation"))
      return {};
    const auto &value = preferences.at("navigation");
    const auto get = [&](const char *key, bool fallback) {
      const auto it = value.find(key);
      return it != value.end() && it->is_boolean() ? it->get<bool>() : fallback;
    };
    const bool arrows = value.contains("candidate_arrow_navigation")
                            ? get("candidate_arrow_navigation", true)
                            : get("arrows", true);
    return {get("minus_equal", true), get("comma_period", true),
            get("brackets", false), get("tab", true),
            get("page_up_down", true), get("mouse_wheel", false), arrows};
  }

  std::optional<uint32_t> wheel_command(guint button) const {
    if (!mouse_wheel)
      return std::nullopt;
    if (button == 4)
      return MSIME_PREVIOUS_PAGE;
    if (button == 5)
      return MSIME_NEXT_PAGE;
    return std::nullopt;
  }

  std::optional<uint32_t> command(guint key, bool shift) const {
    // Windows touch keyboards emit private-use page commands. Handle these
    // before configurable bindings so the compatibility events are not
    // swallowed when ordinary page shortcuts are disabled.
    if (const auto touch = touch_keyboard_command(key))
      return touch;
    if (tab &&
        (key == IBUS_Tab || key == IBUS_KP_Tab || key == IBUS_ISO_Left_Tab))
      return shift || key == IBUS_ISO_Left_Tab ? MSIME_PREVIOUS_PAGE
                                               : MSIME_NEXT_PAGE;
    if (page_up_down) {
      if (key == IBUS_Page_Up || key == IBUS_KP_Page_Up)
        return MSIME_PREVIOUS_PAGE;
      if (key == IBUS_Page_Down || key == IBUS_KP_Page_Down)
        return MSIME_NEXT_PAGE;
    }
    if (arrows) {
      if (key == IBUS_Up || key == IBUS_KP_Up)
        return MSIME_PREVIOUS_CANDIDATE;
      if (key == IBUS_Down || key == IBUS_KP_Down)
        return MSIME_NEXT_CANDIDATE;
    }
    // Shifted symbols remain text (not physical-key aliases). In particular,
    // Unicode '+' must reach Engine even when equal-key paging is enabled.
    if (!shift) {
      if ((minus_equal && key == IBUS_minus) ||
          (comma_period && key == IBUS_comma) ||
          (brackets && key == IBUS_bracketleft))
        return MSIME_PREVIOUS_PAGE;
      if ((minus_equal && key == IBUS_equal) ||
          (comma_period && key == IBUS_period) ||
          (brackets && key == IBUS_bracketright))
        return MSIME_NEXT_PAGE;
    }
    return std::nullopt;
  }
};

inline bool navigation_key(guint key) {
  switch (key) {
  case IBUS_Tab:
  case IBUS_KP_Tab:
  case IBUS_ISO_Left_Tab:
  case IBUS_Page_Up:
  case IBUS_KP_Page_Up:
  case IBUS_Page_Down:
  case IBUS_KP_Page_Down:
  case IBUS_Up:
  case IBUS_KP_Up:
  case IBUS_Down:
  case IBUS_KP_Down:
  case kTouchKeyboardNextPage:
  case kTouchKeyboardPreviousPage:
    return true;
  default:
    return false;
  }
}
} // namespace msime::linux_host

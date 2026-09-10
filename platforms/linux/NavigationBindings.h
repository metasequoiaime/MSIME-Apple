#pragma once
#include "msime_client.h"
#include <ibus.h>
#include <nlohmann/json.hpp>
#include <optional>

namespace msime::linux_host {
// Host key bindings only. Candidate movement and paging belong to the shared
// runtime. IBus key values describe the active keyboard layout, not Windows
// VKs.
struct NavigationBindings {
  bool minus_equal = true;
  bool comma_period = true;
  bool brackets = false;
  bool tab = true;
  bool page_up_down = true;
  bool arrows = true;

  static NavigationBindings read(const nlohmann::json &preferences) {
    if (!preferences.contains("navigation"))
      return {};
    const auto &value = preferences.at("navigation");
    return {value.at("minus_equal").get<bool>(),
            value.at("comma_period").get<bool>(),
            value.at("brackets").get<bool>(),
            value.at("tab").get<bool>(),
            value.at("page_up_down").get<bool>(),
            value.at("arrows").get<bool>()};
  }

  std::optional<uint32_t> command(guint key, bool shift) const {
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
    return true;
  default:
    return false;
  }
}
} // namespace msime::linux_host

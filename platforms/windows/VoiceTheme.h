#pragma once
#include <string_view>

namespace msime::windows {
// Match the shared panel: an explicit surface wins, then the global theme,
// and only a global system preference consults Windows.
inline bool voice_theme_is_light(std::string_view surface,
                                 std::string_view global, bool system_dark) {
  if (surface == "light")
    return true;
  if (surface == "dark")
    return false;
  return global == "light" || (global == "system" && !system_dark);
}
} // namespace msime::windows

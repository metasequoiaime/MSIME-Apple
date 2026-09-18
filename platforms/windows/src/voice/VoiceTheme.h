#pragma once
#include <string_view>

namespace msime::windows {
enum class SurfaceThemeMode { Dark, Light, System };

inline SurfaceThemeMode surface_theme_mode(std::string_view surface,
                                           std::string_view global) {
  if (surface == "light")
    return SurfaceThemeMode::Light;
  if (surface == "dark")
    return SurfaceThemeMode::Dark;
  if (global == "light")
    return SurfaceThemeMode::Light;
  if (global == "system")
    return SurfaceThemeMode::System;
  return SurfaceThemeMode::Dark;
}

inline bool surface_theme_is_light(SurfaceThemeMode mode, bool system_dark) {
  return mode == SurfaceThemeMode::Light ||
         (mode == SurfaceThemeMode::System && !system_dark);
}

// Match the shared panel: an explicit surface wins, then the global theme,
// and only a global system preference consults Windows.
inline bool voice_theme_is_light(std::string_view surface,
                                 std::string_view global, bool system_dark) {
  return surface_theme_is_light(surface_theme_mode(surface, global),
                                system_dark);
}
} // namespace msime::windows

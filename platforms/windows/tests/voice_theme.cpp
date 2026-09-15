#include "../VoiceTheme.h"
#include <cassert>
#include <string_view>

int main() {
  using msime::windows::SurfaceThemeMode;
  using msime::windows::surface_theme_is_light;
  using msime::windows::surface_theme_mode;
  using msime::windows::voice_theme_is_light;
  for (bool system_dark : {false, true}) {
    for (std::string_view global : {"dark", "light", "system"}) {
      assert(voice_theme_is_light("light", global, system_dark));
      assert(!voice_theme_is_light("dark", global, system_dark));
      assert(voice_theme_is_light("follow", global, system_dark) ==
             (global == "light" || (global == "system" && !system_dark)));
    }
  }
  assert(surface_theme_mode("light", "system") == SurfaceThemeMode::Light);
  assert(surface_theme_mode("dark", "system") == SurfaceThemeMode::Dark);
  assert(surface_theme_mode("follow", "light") == SurfaceThemeMode::Light);
  assert(surface_theme_mode("follow", "dark") == SurfaceThemeMode::Dark);
  assert(surface_theme_mode("follow", "system") == SurfaceThemeMode::System);
  assert(surface_theme_is_light(SurfaceThemeMode::System, false));
  assert(!surface_theme_is_light(SurfaceThemeMode::System, true));
}

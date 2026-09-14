#include "../VoiceTheme.h"
#include <cassert>
#include <string_view>

int main() {
  using msime::windows::voice_theme_is_light;
  for (bool system_dark : {false, true}) {
    for (std::string_view global : {"dark", "light", "system"}) {
      assert(voice_theme_is_light("light", global, system_dark));
      assert(!voice_theme_is_light("dark", global, system_dark));
      assert(voice_theme_is_light("follow", global, system_dark) ==
             (global == "light" || (global == "system" && !system_dark)));
    }
  }
}

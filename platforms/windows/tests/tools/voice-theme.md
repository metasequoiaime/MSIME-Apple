# Voice overlay theme

The native overlay uses the same precedence as the shared voice panel:
explicit voice theme, global theme, then system appearance only when the
global setting is `system`. Startup and preference updates use one helper.

Local regression check (18 combinations of surface/global/system):

```sh
c++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  tests/voice/voice_theme.cpp -o /tmp/msime-voice-theme-test
/tmp/msime-voice-theme-test
x86_64-w64-mingw32-g++ -std=c++17 -Wall -Wextra -Werror \
  tests/voice/voice_theme.cpp -o /tmp/msime-voice-theme-test.exe
```

The host-side sanitizer test executes the policy, not Win32. The Windows
test binary is cross-compiled only. Neither verifies the complete Server
build, native overlay rendering, or live OS appearance-change notifications.

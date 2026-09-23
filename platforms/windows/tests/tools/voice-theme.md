# Voice overlay theme

The native overlay uses the same precedence as the shared voice panel: explicit voice theme, global theme, then system appearance only when the global setting is `system`. Startup and preference updates go through one helper.

Local regression check (CTest `windows-voice-theme`; the 18 surface/global/system combinations), run from the repository root:

```sh
c++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  platforms/windows/tests/voice/voice_theme.cpp -o target/voice-theme-test
./target/voice-theme-test
x86_64-w64-mingw32-g++ -std=c++17 -Wall -Wextra -Werror \
  platforms/windows/tests/voice/voice_theme.cpp -o target/voice-theme-test.exe
```

The host-side sanitizer run executes the precedence policy, not Win32. The second command checks that the same source compiles for the Windows target; `../../run-tests-wine.sh` runs the built suite, and the overlay's actual rendering and live appearance-change notifications belong to the Server on Windows.

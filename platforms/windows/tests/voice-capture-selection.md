# Windows capture selection

The Tauri device command enumerates Engine capture endpoint identities on a
blocking worker. It returns the existing `{backend, id, label}` shape with
`backend: "windows"`; the ID is no longer an enumeration index. Labels and
endpoint IDs can identify user hardware and must not be logged.

The shared preference store persists `voice_input.capture_backend` and
`capture_device`. The Server's preference observer copies these into
`VoiceInputConfig`; both native-hotkey and controller-review recording pass
the captured ID to Engine when starting. Updates do not switch an active
recording's device. Empty, `auto`, and `windows` backends are supported here;
foreign backends fail before starting recognition. Empty IDs select the system
default. Nonempty stale/invalid IDs fail rather than recording another device.

Previously saved numeric indices were never honored by the native capture
path. They are deliberately not reinterpreted: refresh and choose an endpoint,
or clear the selection to explicitly use the system default.

Manual checks (no microphone required):

```sh
c++ -std=c++17 -Wall -Wextra -Werror -fsanitize=address,undefined \
  -I/opt/homebrew/include platforms/windows/tests/voice_capture_selection.cpp \
  -o target/voice-capture-selection
./target/voice-capture-selection
pnpm --filter @msime/desktop exec vitest run src/windows-capture-devices.test.tsx
pnpm --filter @msime/desktop build
```

The C++ test uses synthetic configuration; UI tests use synthetic same-label
devices and reorder their list. Engine's synthetic capture-device tests verify
the same ID resolver used by production, including ambiguous/missing IDs and
invalid syntax rejected before device initialization. These tests and GNU
cross-compilation do not establish native microphone/permission behavior.

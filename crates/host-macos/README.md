# macOS shared panel host

This platform crate has no Tauri, React, desktop application or Engine dependency. It translates the existing shared keyboard request into ANSI macOS hardware codes and wraps main-thread AppKit/CoreGraphics operations. Input algorithms and composition remain in the Engine/native IMK host.

Windows reference: `metasequoiaime/MSIME-Windows`, actual default branch `develop`, commit `0765bfb88de553ade41901d853d3f6d697accde7`, `server/src/keyboard-panel/KeyboardPanel.cpp`. Keyboard keys target the external process captured when the non-activating Tauri keyboard panel mounts. The PID is paired with its launch time and revalidated for every stroke, so a settings window cannot receive keys and a recycled PID cannot receive stale input. Sticky modifiers follow the shared commit-key contract; Win and Alt become Command and Option. PC-only keys without a macOS equivalent are not mapped.

The desktop adapter uses `tauri-nspanel` pinned to `c9ec2130422200f0863b23dfdad02b133a529b07`. The platform library itself does not depend on that adapter. WebKit content is detached before window-class conversion and restored afterward, including the close path, so its KVO observations follow the correct window class. The detached content guard cannot move off the main thread.

Permission checks never prompt. A key is rejected if posting is unavailable, the captured process is this process, has exited, or has a different launch identity, or event allocation fails. The live-foreground fallback also rejects a focus change before posting. Startup focus restoration applies only when this shell is still foreground and the original process identity/launch time still matches; it does not send a pending key or steal focus from another application.

Local verification:

```sh
MACOSX_DEPLOYMENT_TARGET=13.0 cargo test -p msime-host-macos -p msime-desktop --lib
MACOSX_DEPLOYMENT_TARGET=13.0 cargo clippy -p msime-host-macos -p msime-desktop --lib --tests
MACOSX_DEPLOYMENT_TARGET=13.0 cargo run -p msime-desktop --example macos_keyboard_window_check
```

The example uses real Wry/AppKit windows, kept hidden, to verify NSPanel properties and create/restore/close/reopen lifecycle. It never posts input or requests permission. `platforms/macos` CMake also registers `shared-keyboard-host` and `desktop-settings-launcher` tests; these test event construction and failure guards using synthetic OS boundaries, and launch configuration using a test workspace.

These checks do not claim an installed IMK-to-editor typing test. Emoji/handwriting/cloud panel input-session and service bridges remain separate migration work; only keyboard startup routing is enabled by this increment. CI remains disabled.

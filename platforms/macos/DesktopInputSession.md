# Shared text-tool input sessions

The native IMK emoji and handwriting menus launch their shared Tauri panels in a new
application instance. It captures the exact weak IMK client and generation before
launch. Shared settings launches without this context cannot insert text through
this bridge. A session is limited to the launching route: another tool window in
that process cannot submit or cancel it. Native launch-failure fallbacks retain
the same captured target; the handwriting fallback closes only after an accepted
selection, and standalone native handwriting copies instead of guessing a client.

## Packaged handwriting

The macOS Tauri bundle includes the fixed Engine handwriting model under
`Contents/Resources/handwriting`, together with the Tegaki model license, Zinnia
license, and upstream provenance. Discovery is relative to the running executable
so moving the application does not break recognition. Explicit host options and
provider/model overrides retain precedence.

The C++ Engine performs single-character ordered-stroke recognition. This is not
sentence segmentation or image OCR. An exploratory Apple Vision adapter executed
successfully but returned no candidates for the tested isolated glyphs; it was
removed rather than treating a successful API call as handwriting parity. The
shared panel uses the actual packaged Engine implementation without needing a
separate recognizer service. Recognition and composition algorithms remain out
of the platform host and UI.

Build with `pnpm --filter @msime/desktop tauri build --debug --bundles app --no-sign`
for an unsigned local bundle. Signing, installation, and live-editor checks are
separate from this local build.

The session environment contains protocol version, a private temporary Unix socket
path, the native host PID, and the original application PID and launch time. It
never reaches JavaScript and contains no composed text or credential. A 0700
directory and 0600 socket restrict access; both endpoints additionally verify
kernel-provided UID and PID. The native endpoint authorizes only the launched
application and checks that it remains alive.

A request is a four-byte big-endian UTF-8 byte length followed by at most 4096
bytes and write EOF. NUL, invalid UTF-8, trailing bytes, and truncated frames are
rejected. Zero length cancels an unused session. A single response byte is 0 for
confirmed native insertion and 1 for rejection. Transport failure after writing
is an unknown outcome, never an automatic retry. A session allows one submission,
expires after five minutes, and removes its socket and directory when stopped.

On selection, Tauri checks the target application's launch identity and refuses
to take focus from a third application, restores the original application, hides
the panel, and submits on a blocking worker. IMK retains ownership of exact-client
validation and insertion. Its pending text expires at the transport's monotonic
deadline (at most two seconds), and only an actual insert call acknowledges
success. Close and submit are serialized; cancellation does not insert text.
Neither component uses accessibility text injection or requests permissions.

## Local verification

- `cargo test -p msime-host-macos` covers real Unix transport framing, wrong-peer
  rejection, lost acknowledgements, input bounds, and invalid configuration.
- `cargo test -p msime-desktop --lib` covers shared tool startup routing, route
  isolation, mutually exclusive close/submit, and real Engine recognition of
  synthetic Chinese strokes from a relocated bundle-shaped resource directory.
- `desktop-input-session-test` covers native framing, cancellation, refusal,
  malformed requests, duplicate completion, permissions, and cleanup.
- Build `cargo build -p msime-host-macos --example panel_session_probe`, configure
  CMake with `MSIME_PANEL_SESSION_PROBE` pointing to that binary, and run
  `desktop-input-interop` for a real Rust child process/native listener exchange.
- `desktop-settings-launcher-test` checks route/environment propagation and the
  main-thread launch authorization callback. `tool-text-return-test` checks
  exact-client, generation, and expiration guards.
- Build `MSIMEClientInputMethod` to compile the actual Objective-C IMK integration.

Tests use synthetic input without activating editors or installing an input method.
They do not establish live-editor behavior. Cloud-panel input return and creating
native sessions from standalone shared settings remain separate work.
The upstream Windows baseline for this increment is develop commit
`bc5e86fa6d809036c142d209900fdc014614d7b0`.

# Shared emoji input session

The native IMK emoji menu launches the shared Tauri emoji panel in a new
application instance. It captures the exact weak IMK client and generation before
launch. Shared settings launches without this context cannot insert text through
this bridge. The existing native emoji fallback remains available on launch failure.

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
- `cargo test -p msime-desktop --lib` covers shared emoji startup routing and the
  mutually exclusive close/submit lifecycle, alongside desktop regression tests.
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
They do not establish live-editor behavior. Handwriting, cloud-panel input return,
and creating native sessions from standalone shared settings remain separate work.
The upstream Windows baseline for this increment is develop commit
`bc5e86fa6d809036c142d209900fdc014614d7b0`.

# Shared cloud clipboard account bridge

The native IMK menu launches the Tauri cloud clipboard surface while the existing
Swift account actor remains the sole owner of account credentials and refreshes.
Signed-out and failed launches retain the native clipboard window fallback.
When the menu belongs to an active IMK client, it also captures a one-shot input
session before launching the panel. Standalone launches retain local copy.

## Boundaries

- `BackendCloudClipboardProvider` captures the native account ID when preparing
  the panel. Credentials are checked before and after each request; logout or a
  different account prevents delivery of a pending response. Tokens never cross
  the transport or enter host-core configuration.
- `DesktopCloudClipboardSession` exposes a private 0700 temporary directory and
  0600 Unix socket. Both ends verify kernel peer UID and the exact peer PID.
  Only the explicitly launched desktop process is authorized. Its exit removes
  the endpoint. Startup authorization expires after 30 seconds.
- `MSIME_CLIENT_CLOUD_CLIPBOARD_SESSION` contains only version, socket path and
  native host PID. It is not a general account service. The Tauri dispatcher
  accepts it only from `cloud-clipboard-panel`. An explicitly configured provider
  retains precedence over this native session.
- Each connection carries one 4-byte big-endian length, JSON request and write
  EOF. Requests are bounded to 64 KiB and responses to 2 MiB. The serial native
  worker has bounded read/provider waits and cancellation. Mutations are never
  automatically retried after an uncertain response.
- Supported operations are list, add, delete by ID and set enabled. Text supports
  4000 UTF-16 units including multiline/tab content. No automatic clipboard read
  is introduced. The shared UI asks for confirmation before disabling, because
  that operation deletes cloud history, and removes stale history on list failure.

## Local regression coverage

The Swift provider test injects a synthetic account/API: validation, cancellation,
signed-out mutation rejection and account changes during I/O need no network or
keychain access. The native/Rust interop test runs a real child process, validates
all four operations, multiline Unicode framing, filesystem permissions and peer
exit cleanup. Rust tests cover wrong host PID, invalid configuration, truncated
or oversized responses and absence of mutation retries. Shared UI tests cover
copy-only capability, destructive confirmation and stale-history removal.

Configure CMake with `MSIME_CLOUD_CLIPBOARD_PROBE` pointing to the Cargo
`cloud_clipboard_probe` example, then build `desktop-cloud-clipboard-interop-test`
and `desktop-cloud-provider-test-build`; run `ctest -R desktop-cloud`.

## Follow-ups

The shared panel queries native input capability; only the launching clipboard
route with an unused clipboard-type input session may submit. The native helper
passes both the account and input endpoints to the same authorized child process.
Submission hides the panel, restores the captured application and waits for the
exact IMK client to acknowledge insertion. Text is limited to 4000 UTF-16 units,
including CR/LF/tab; candidate sessions retain their original limits. Lost
acknowledgements are never retried. See `DesktopInputSession.md` for the contract.

Standalone Tauri account/input-session integration remains separate. Builds and
synthetic transport tests do not establish installed
IMK/live-editor integration or live cloud-account behavior.

Reference baseline: MSIME-Windows default branch `develop` at
`cb534a97fd19bc9656645a7baa4ee019487279a8`; Engine lock
`f0d212c8a90dac2f70d48a5a149e4f71080b4e7b`.

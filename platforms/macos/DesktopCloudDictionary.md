# Native-account shared dictionary RPC

The native cloud dictionary route launches the shared Tauri dictionary panel with `MSIME_CLIENT_CLOUD_DICTIONARY_SESSION`. The existing Swift account actor remains the only credential/refresh owner. The provider pins the account ID at launch and checks it before and after I/O. Credentials never cross IPC. Signed-out or failed launches return to the native account window, where the existing native tools remain.

## Supported shared panel operations

List all four dictionary kinds with offset/search, add, update, delete, import (standard/Windows TSV and pinyin automatic annotation), and export (standard and Windows TSV). Updates/deletes preserve the supplied positive revision; a backend 409 becomes the sanitized `conflict` error, never an automatic retry. Both the desktop contract and native provider validate requests before network mutation. List failure clears stale shared-panel entries and editing state.

The same authenticated webview also hosts the complete catalog and candidate ranking subpages. Catalog requests preserve scheme/profile, normalization, paging and revision zero for unmodified base entries. Edits send explicit null for deletion. Candidate requests preserve canonical pinyin separately from display codes; mutations use that canonical identity. All five ranking modes, selection counters, removal, fixed positions 1–5 and unfixing use the native account API. Position operations do not require a dictionary-kind field. Validation rejects boolean-as-integer values and malformed replacement/position payloads before I/O. Failed catalog/candidate lookups clear their stale entries, editing targets and ranking context; a failed secondary fixed-position read does not discard a successfully received candidate page.

The authenticated RPC implementation is shared with cloud clipboard transport, but the launch environment and permitted webview label remain separate. Only `cloud-dictionary-panel` may use this native dictionary session. Explicit provider configuration or environment overrides retain precedence. Main settings stays hidden during a panel-only launch; closing the last panel ends that instance.

## Export and lifetime contract

- Dictionary request JSON allows 512 KiB so escaped 64 KiB import text fits; clipboard requests retain their existing 64 KiB envelope. Responses remain bounded to 2 MiB.
- Dictionary exports retain the 384 MiB native stream-to-file limit. The response contains a private export descriptor, not file contents. The desktop worker opens the directory/file without following final symlinks and verifies the expected filename, private modes, current UID, regular file type, single link and exact bounded length. Handles remain pinned while reading.
- The descriptor is consumed in Rust. JavaScript receives only the exported text and a fixed dictionary filename for its download UI. Paths and account credentials do not reach the webview.
- The provider owns exports until replacement or session destruction. A failed post-download account check removes the pending file without exposing it.
- Normal requests keep a 35-second native response wait; exports allow 605 seconds to match the 600-second downloader. Peer authorization is checked while waiting, and losing the panel cancels the native Progress/Task. Uncertain mutations are not retried.

## Local verification

`desktop-dictionary-provider-test` injects a synthetic API/account and checks paging, validation, revisions/conflicts, import formats, exports larger than 2 MiB, cleanup and account changes. `desktop-cloud-dictionary-interop` runs the Rust `cloud_dictionary_probe` example against a real native socket and private file. `desktop-account-cancellation` checks cancellation when peer authorization is lost. Rust tests additionally reject symlinks/incorrect metadata and prove that exported paths are consumed before forming the webview response.

Configure CMake with `MSIME_CLOUD_DICTIONARY_PROBE` pointing to the Cargo example, build `desktop-cloud-dictionary-interop-test`, `desktop-dictionary-provider-test-build` and `desktop-account-cancellation-test`, then run the matching CTest entries. Full dictionary snapshot restore is a separate path with its own contract; see `LOCAL_SNAPSHOT_INTEGRATION.md`.

Reference baseline: MSIME-Windows default branch `develop` at `cb534a97fd19bc9656645a7baa4ee019487279a8`. The authoritative Engine pin is `engine-lock.json`.

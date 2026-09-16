# Portable voice controller interoperability

Run from the repository root after preparing the locked Engine sources:

```sh
python3 scripts/fetch_engine.py
bash platforms/windows/tests/voice-wire-interop.sh
rustfmt --check --edition 2021 platforms/windows/tests/voice_wire_interop.rs
clippy-driver --edition=2021 --test -D warnings platforms/windows/tests/voice_wire_interop.rs -o target/voice-wire-interop/clippy-tests
```

Requires a host C++17 compiler with AddressSanitizer/UndefinedBehaviorSanitizer
and Rust. The runner compiles the real client-core controller module and the
real C++ dispatcher/codec against the pinned Engine contract. A subprocess
exchanges exact v2 messages inside bounded test-only length prefixes. Replies
have a two-second receive deadline; teardown kills and reaps the peer.

Synthetic cases cover recording level, stop-once/poll progression, Unicode
review output, mismatched request/session IDs, cancellation, failure and peer
disconnect. The three existing Rust controller unit tests run alongside the
two interoperability tests. No microphone, credentials, input injection or
clipboard is used. This does not test named-pipe authentication, the Windows
listener, focus transitions, device capture or native Tauri events.

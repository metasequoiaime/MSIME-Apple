# Shared voice provider adaptation

`msime-voice-providers` contains the provider defaults, HTTP recognition and
polishing adapter extracted unchanged from `platforms/windows/src/VoiceProviders.h`
at the shared client repository, commit `f78cf0fdf4f58d3e9405faec3158ed216b17ec78`.
It uses the pinned Engine voice protocol/WAV library and has no desktop UI,
Windows API, host-process, or microphone dependency.

New native hosts include `VoiceProviders.h` and use `msime::voice`. The historical
`msime::windows` symbols remain for compatibility, with a forwarding header at
the old Windows include path. There is only one implementation. No TSF/Server
protocol or process ownership changes are involved.

Hosts must supply bounded mono 16 kHz PCM, configuration, cancellation and a
worker queue, then validate session/focus before applying results. This module
does not capture audio or implement Doubao WebSocket transport. Linking it into
the macOS build is not evidence that macOS cloud recording is fully integrated.

Standalone local validation:

```sh
cmake -S shared/voice -B build/shared-voice -DBUILD_TESTING=ON
cmake --build build/shared-voice
ctest --test-dir build/shared-voice --output-on-failure
```

The synthetic routing test exercises the platform-neutral entry points and
pre-cancelled requests without contacting cloud services. Engine tests also
exercise audio and HTTP contracts using a local fixture server.

`DoubaoAuth.h` is a thin C++ adapter for `client-core::doubao_auth` through
`msime_client_doubao_auth_headers`. It requires the host-api include path and
library. Both the Rust credential probe and native Windows recording use this
same authentication policy: explicit `api_key` ignores stale App IDs, explicit
`legacy` requires an App ID, and missing historical modes infer from a usable
App ID. Returned header text contains credentials and must never be logged.
Pass an absolute `MSIME_HOST_LIBRARY` when configuring this project to enable
the synthetic C++/Rust ABI test `shared-doubao-auth`.

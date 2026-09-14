# Shared voice provider adaptation

`msime-voice-providers` contains the provider defaults, HTTP recognition and
polishing adapter extracted unchanged from `platforms/windows/VoiceProviders.cpp`
at MSIME-Client `f78cf0fdf4f58d3e9405faec3158ed216b17ec78`.
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

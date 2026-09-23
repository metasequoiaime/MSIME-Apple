# Server manifest link probe

The production Server includes `ServerManifest.cmake`. This minimal target uses the same wiring without starting the Server or registering a TSF component, so a manifest change can be checked without a full platform build.

`MSIME_SERVER_UIACCESS` defaults to OFF, which is what a development build wants; `Build-Client.ps1` turns it on for the x64 installation build only. The manifest matches MSIME-Windows commit `342e2b6b2cb265ddc56d9d35cae642a4b696d73b` (`server/MetasequoiaImeServer.manifest`): `asInvoker`, `uiAccess="true"`. UIAccess takes effect only for a trusted-signed binary in a secure installation location — that is what the signed installer produces. The option neither elevates Tauri nor bypasses Windows trust requirements.

Local cross-link verification, run from the repository root:

```sh
cmake -S platforms/windows/tests/server-manifest -B /tmp/msime-manifest-probe \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
  -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
  -DMSIME_SERVER_UIACCESS=ON
cmake --build /tmp/msime-manifest-probe
x86_64-w64-mingw32-windres -J coff -O rc /tmp/msime-manifest-probe/msime-client-server.exe
```

The extracted PE must contain RT_MANIFEST (24), resource ID 1, and `requestedExecutionLevel` with `asInvoker` and `uiAccess="true"`. A native configure and build with the option OFF must work without an RC compiler. MSVC disables linker-generated manifests because RC already embeds resource 1. This probe checks the embedded resource; the signed Server it stands in for is built by `../../Build-Client.ps1` and signed and installed through `../../installer/Package-SimplySign.ps1`.

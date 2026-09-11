# TSF development host configuration

The TIP reads `%LOCALAPPDATA%\MSIME-Client\runtime-options.json`, not legacy
product state or guessed paths relative to the embedding application.

With all sessions using this development state stopped, prepare it through the
shared host tool (PowerShell, from the repository root):

```powershell
cargo run -p msime-host-api --example prepare_host -- '<verified-resource-directory>' "$env:LOCALAPPDATA\MSIME-Client"
```

The tool verifies locked resources, prepares Engine working data, loads shared
preferences and atomically publishes the complete document. The TIP reads up to
the C ABI limit of 16384 bytes and passes it unchanged to the host. Missing,
empty, unreadable or oversized files do not create a session; malformed schema
and invalid preferences are rejected by the shared host. This does not install
or register the TIP, or provide automatic resource updates.

Native focus is routed through activation, document/top-context changes, deferred
loss and deactivation; repeated same-context notifications are deduplicated because
runtime focus resets composition. Preference monitoring, full DLL builds and
installed-editor focus validation remain outstanding; initialization is not platform completion.

## COM export contract

The production DLL links `IME/MetasequoiaIME.def` to expose the four undecorated
COM entry points on x86 and x64. A standalone link-only fixture tests this same
definition without requiring the complete SDK-dependent TIP:

```sh
cmake -S platforms/windows/tsf/tests/exports -B target/tsf-exports-x64 -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++
cmake --build target/tsf-exports-x64
ctest --test-dir target/tsf-exports-x64 --output-on-failure
```

Use a separate directory and `i686-w64-mingw32-g++` for x86. Tests inspect PE
exports and reject a DLL missing the COM symbols; they never load or register
the fixture. An MSVC build uses `dumpbin`. These checks do not establish that
the full TIP builds, registers or handles input.

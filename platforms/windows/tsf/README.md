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

Native focus wiring, preference monitoring, full DLL builds and installed-editor
validation remain separate requirements; initialization is not platform completion.

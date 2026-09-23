# Windows shared-host preparation

`msime-client-prepare.exe` is a native command-line entry point for the shared Host API. It verifies the pinned desktop resources and asks the shared Engine bridge to prepare writable dictionaries. It does not implement input algorithms, register TSF, start processes, or change system settings.

Build the `msime-client-prepare` CMake target with `MSIME_HOST_LIBRARY` pointing to the same-architecture Rust Host API import library; its DLL must be available at runtime. The executable is included in CMake's `bin` installation.

Run as the intended input-method user, before starting Server or TSF:

```powershell
& .\msime-client-prepare.exe 'C:\MSIME Resources' "$env:LOCALAPPDATA\MSIME-Client"
```

The resource directory must contain the bundle required by `resources/desktop-dictionary.lock.json`. Both arguments must be absolute. The state directory must not exist and its parent must exist. For the production Server and TSF, use the LocalAppData path above. The new directory inherits its parent's Windows permissions; do not run this command as an elevated installer or point it at a shared writable parent.

Preparation never overwrites an existing state directory. The complete JSON is published as `runtime-options.json` using a same-directory hard link, without replacing an existing destination. The filesystem must support hard links (normally NTFS). Errors retain partially prepared data and emit generic messages, not raw Host API diagnostics. This command is for fresh preparation, not upgrades or automatic recovery; do not delete an existing state directory to force retry.

The production Server runs the same preparation orchestration in its own user context when the LocalAppData state directory does not exist. It uses the verified bundle staged beside the executable in `resources`, after the production single-instance check and before reading runtime options. The installer does not launch this standalone command or prepare state elevated. Both `--production` and `--watchdog-managed` use this path; `--config` does not. Existing directories, including incomplete preparation, are never rebuilt automatically — a state directory that was left half-prepared has to be removed deliberately by the user.

`tests/runtime/prepare_host.cpp` (CTest `windows-prepare-host`) exercises the orchestration with synthetic Host API responses: publication, invalid paths, refusal of existing state, failed host responses, and concurrent destination preservation. It uses synthetic responses rather than the pinned resource bundle, so it checks the orchestration rather than the dictionary contents; `run-smoke.ps1 -ResourcesDirectory` covers the latter against a real locked generation.

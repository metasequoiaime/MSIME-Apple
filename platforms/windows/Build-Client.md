# Client Windows build entry

Run `Build-Client.ps1` in a Windows MSVC environment with CMake, Cargo, pnpm,
the x86_64-pc-windows-msvc and i686-pc-windows-msvc Rust targets, and the
repository's pinned Engine submodule initialized. Supply separate absolute
native dependency prefixes with the packages listed in `vcpkg.json`:

```powershell
.\platforms\windows\Build-Client.ps1 -X64Dependencies C:\deps\x64 -X86Dependencies C:\deps\x86
```

The default CMake generator is Visual Studio 2022. Each prefix must contain
libraries built for its architecture and a compatible MSVC runtime; this script
does not download or build dependencies, alter Rust toolchains, sign binaries,
register TSF, invoke CI, or install the input method.

The x64 build includes Server, Watchdog, preparation tool and TSF. The x86
build contains the in-process TSF and matching Host DLL, not another Server.
Native outputs go to `target/windows-full/<arch>/bin`. Rust release artifacts
remain under the explicit target triple, with debug information enabled;
native CMake uses RelWithDebInfo. The x64 dictionary replay executable and PDB
are copied beside Server. Tauri is built for x64 without bundling, typechecked,
and staged as `msime-client-settings.exe` in the x64 bin directory.

Every native command exit status is checked immediately. The caller's directory,
dependency prefix, Cargo target directory and release-debug setting are restored
on success or failure. `tests/build_client.ps1` tests the orchestration using
command probes, including failure at every stage; it does not compile native
code or prove runtime dependency closure.

The legacy `installer/test.ps1` and `test-light.ps1` are not yet migrated to this
entry and should not be used as Client build verification. Native dependency DLL
collection, architecture-correct installer staging, legacy asset removal and
full Windows build/installation verification remain unfinished.

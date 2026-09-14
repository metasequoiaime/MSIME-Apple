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

Before reporting completion, the build reads PE headers from all five x64 EXE
outputs and the TSF/Host DLL pair for each architecture. It rejects missing or
truncated headers, wrong machine or optional-header type, and EXE/DLL flag
mismatches. `Test-PortableExecutable.ps1` can also inspect individual outputs
without loading them. Header fields follow Microsoft's
[PE format specification](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format).
This is an architecture/type gate, not full image validation, signature checking,
import resolution or Windows runtime verification. Parser fixtures intentionally
contain only synthetic headers; they are not executable images.

The build also collects top-level release `bin/*.dll` from each explicitly
provided dependency prefix. Every candidate passes the PE architecture/DLL gate
before copying; same-named different output content causes failure rather than
overwrite. Identical files are reused. Static prefixes may have no bin directory.
Debug subdirectories and non-DLL files are not copied. Each TSF staging directory
carries these ordinary dependencies without COM registration; the Server package
already copies its output directory recursively.

This collects all release DLLs from the supplied prefixes, not only imported
ones. It is not recursive import analysis: Windows components, VC runtime
redistribution and dynamically loaded modules outside those prefixes still need
explicit provisioning and verification. Distribution must retain the licenses
for supplied dependency packages; prefix collection is not a license audit.

The legacy `installer/test.ps1` and `test-light.ps1` are not yet migrated to this
entry and should not be used as Client build verification. Legacy asset removal,
full dependency closure and Windows build/installation verification remain
unfinished.

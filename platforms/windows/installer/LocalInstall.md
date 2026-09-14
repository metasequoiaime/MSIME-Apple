# Client local installation workflow

The full `test.ps1` and existing-installation-only `test-light.ps1` wrappers use
`Invoke-LocalInstall.ps1` and the actual Client `Build-Client.ps1`. They no longer
reference legacy windows/scripts, server/scripts or ui-html build projects.

```powershell
.\platforms\windows\installer\test.ps1 -X64Dependencies C:\deps\x64 -X86Dependencies C:\deps\x86 -NoticesDirectory target/windows-notices
```

This is an explicit local build/sign/install command, not a unit test: the
existing signing scripts create/reuse a local test certificate and may modify
the local trust store, and the final stage launches the installer. For building
alone, use `platforms/windows/Build-Client.ps1`. These scripts do not trigger CI.

The shared sequence is Client build, package preparation, binary signing,
Inno compilation, installer signing, then installer launch. Exceptions and
nonzero script/native exit status stop the sequence. The caller's working
directory is restored. Full/light selection is passed consistently through
preparation, compilation, signing and launch. Both architectures are selected
explicitly from target/windows-full, with the Tauri shell beside the x64 Server.

Supply prepared native dependency prefixes and a notice directory containing
THIRD_PARTY_NOTICES.txt. Supplying notices is not a completeness or permission
check; review the limitations in ../Notices.md. Full packages additionally need
the locked DesktopResourcesDirectory (default target/desktop-resources), the
pinned Engine assets and the Windows toolchains documented in ../Build-Client.md.
TargetVersion currently sets installer metadata; coordinated native/Tauri build
version stamping remains a follow-up.

`tests/installer_entry.ps1` substitutes every side-effect stage and verifies
ordering, arguments, light-mode propagation, missing notices, and failure at all
six stages. It does not sign, compile or install. The historical
tests/build-failures.ps1 entry forwards to this regression instead of referring
to removed component scripts. Actual native registration, UIAccess behavior,
dependency closure and installation execution remain unverified.

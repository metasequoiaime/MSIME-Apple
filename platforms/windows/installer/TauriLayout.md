# Windows UI package layout

`Prepare-PackageFiles.ps1` does not require or copy `ui-html/webview2`. The Windows settings product is the native WinUI 3 `msime-client-settings.exe`. The shared desktop UI is still built from `apps/desktop` for the panel shell and is staged as `MSIME Client Preview.exe`. Candidate and toolbar presentation use the Windows native implementation in `platforms/windows/src/candidate`, not either shell executable.

`UiHtmlDirectory` remains an ignored compatibility argument for callers that still pass it. Neither full nor light package mode needs that directory. Old HTML inside package staging is removed, and the Inno full-data copy excludes HTML even if stale staging was supplied externally. The light package installs the executable UI instead of loose HTML. Preparation does not run the installer or delete any already-installed user directory.

There is no post-build HTML version-string replacement. Tauri preview version metadata is supplied at build time through `Build-Client.ps1 -TargetVersion`; the WinUI 3 settings binary gets the native project version. Installer `TargetVersion` does not patch an embedded frontend after compilation. Installer upgrade cleanup and legacy data migration are defined in `msime_setup.iss` and are unaffected by this layout.

Synthetic package tests run without any ui-html source tree while preserving Tauri executable and native artifact checks. They also verify stale HTML removal in light staging. `tests/tauri-layout.ps1` checks the Inno file rules. These check the packaged file layout, not UI rendering or installation on a machine.

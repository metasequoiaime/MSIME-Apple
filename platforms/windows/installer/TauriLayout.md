# Tauri UI package layout

`Prepare-PackageFiles.ps1` no longer requires or copies `ui-html/webview2`.
The shared desktop UI is built from `apps/desktop` into Tauri's frontendDist;
the installer carries the resulting `msime-client-settings.exe`. Candidate and
toolbar presentation use the existing Windows native implementation.

`UiHtmlDirectory` remains an ignored compatibility argument for callers still
being migrated. Neither full nor light package mode needs that directory. Old
HTML inside package staging is removed, and the Inno full-data copy excludes
HTML even if stale staging was supplied externally. The light package installs
the new executable UI instead of loose HTML. These changes do not run the
installer or delete any already-installed user directory.

The former post-build HTML version-string replacement is removed. Tauri version
metadata must be supplied at build time; installer TargetVersion does not patch
an embedded frontend after compilation. Existing installer upgrade cleanup and
legacy data migration are unchanged and still require separate review.

Synthetic package tests now run without any old ui-html source tree, while
preserving Tauri executable and native artifact checks. They also verify stale
HTML removal in light staging. `tests/tauri-layout.ps1` checks the Inno file
rules. These are not UI rendering or native installation tests.

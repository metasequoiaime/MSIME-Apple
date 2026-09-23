# Shared desktop resources in Windows packages

Full `Prepare-PackageFiles.ps1` runs require the exact resource set in `resources/desktop-dictionary.lock.json`. Download that pinned release's files into `target/desktop-resources`, or pass `-DesktopResourcesDirectory` with an absolute path or a path relative to `RepoRoot`.

Every listed file must match its pinned byte length and SHA-256 before staging directories are reset. Only manifest-listed files are copied, retaining their original names, including `mozc_dictionary_oss_README.txt`. Staged bytes are verified again by `Get-VerifiedDesktopResources.ps1`. The result is `server_exe/resources`; Inno's recursive Server rule installs it under Program Files alongside the native executables. No resource URL is downloaded or followed by this script.

Light packages neither require nor carry this bundle. A stale `resources` directory copied from native build output is removed from light staging, not from the installed application. Full packages likewise replace native-output resources with only verified files.

`app_data` is the second staging destination and has a different consumer: it carries the Engine-side dictionary (`msime.db`, `dict_japanese.dat`, `english.db`, `others.db`), the pinyin and helpcode tables, the audio cues and the factory `config.default.toml`. It reads the same verified `DesktopResourcesDirectory`, including its English database and Japanese notice, so no separate MetasequoiaImeDict checkout is needed; `DictionaryDirectory` is retained only as an ignored compatibility parameter. The Japanese notice keeps its historical destination name under `app_data`, while the shared resource directory keeps the manifest name. Pinyin and the application icon come from `installer/assets`. `HelpCodeDirectory` defaults to `vendor/MSIME-Engine/helpcode` in the locked Engine source tree.

Third-party notice collection is separate from resource staging: packaging still requires `THIRD_PARTY_NOTICES.txt` through `NoticesDirectory`. Do not bypass that requirement or treat these resource checks as a distribution license audit.

`msime-client-prepare.exe` consumes the installed resource directory to create fresh per-user HostOptions. The production Server runs the same preparation flow automatically when its user state directory is absent; an existing state directory is never rebuilt on its own. See `../PrepareHost.md`.

The package fixture (`tests/package-files.ps1`) uses a synthetic manifest and synthetic files, verifies the output hashes, checks both size and same-size hash corruption, excludes unlisted files, preserves previous staging on preflight failure, and checks that light packages omit resources. Synthetic bytes are what make the corruption cases possible; the real release bytes are checked by the pinned length and SHA-256 gate above.

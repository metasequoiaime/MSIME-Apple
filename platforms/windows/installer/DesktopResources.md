# Shared desktop resources in Windows packages

Full `Prepare-PackageFiles.ps1` runs now require the exact resource set in
`resources/desktop-dictionary.lock.json`. Download that pinned release's files
into `target/desktop-resources`, or pass `-DesktopResourcesDirectory` with an
absolute path or a path relative to `RepoRoot`.

Every listed file must match its pinned byte length and SHA-256 before staging
directories are reset. Only manifest-listed files are copied, retaining their
original names, including `mozc_dictionary_oss_README.txt`. Staged bytes are
verified again. The result is `server_exe/resources`; Inno's existing recursive
Server rule installs it under Program Files alongside the native executables.
No resource URL is downloaded or followed by this script.

Light packages neither require nor carry this bundle. A stale `resources`
directory copied from native build output is removed from light staging, not
from the installed application. Full packages likewise replace native-output
resources with only verified files. Legacy app_data staging remains for the
parts of the installer still being migrated.

`msime-client-prepare.exe` can consume the installed resource directory to
create fresh per-user HostOptions. Automatic per-user first-run invocation,
existing-state upgrades and native installation verification remain separate
unfinished integration work. Resource packaging alone does not make a fresh
installation operational.

The package fixture uses a synthetic manifest and synthetic files, verifies
the output hashes, checks both size and same-size hash corruption, excludes
unlisted files, preserves previous staging on preflight failure, and checks
that light packages omit resources. It does not validate real release bytes.

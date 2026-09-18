# Windows packaging layout

The installer consumes a staging directory, not source-tree paths. The
staging script writes these inputs for `msime_setup.iss`:

| Staging path | Contents |
| --- | --- |
| `tsf_dll/32` and `tsf_dll/64` | `MetasequoiaImeTsf.dll` and matching symbols |
| `server_exe` | Windows Server, Tauri `msime-client-settings.exe`, and native resources |
| `app_data` | default configuration and runtime resources |
| `app_data/html` | WebView2 UI assets |

Native CMake targets are expected to come from the configured Windows build
directory. The TSF DLL remains an in-process component and the Server remains
out of process; packaging them together does not change that boundary.

For a release package, run `Sign-PackageBinaries-SimplySign.ps1` after staging.
It selects the connected Certum code-signing certificate, signs every EXE/DLL
under `server_exe` and `tsf_dll` in one signtool invocation, then verifies the
certificate and trusted timestamp on every file. The local test-certificate
script remains separate and must not be used for public releases.

Build the Tauri desktop release before staging. `Prepare-PackageFiles.ps1`
requires `target/release/msime-desktop.exe` by default; use `-DesktopExecutable`
for an absolute path or a path relative to `-RepoRoot` (for example a Cargo
target-triple output directory). Both full and light packages include this
binary under the name resolved by the native shell launcher. A missing binary
is rejected before resetting the existing staging directories. This check
does not replace Windows installation or WebView2 runtime validation.

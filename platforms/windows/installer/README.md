# Windows packaging layout

The installer consumes a staging directory, not source-tree paths. The
staging script writes these inputs for `msime_setup.iss`:

| Staging path | Contents |
| --- | --- |
| `tsf_dll/32` and `tsf_dll/64` | `MetasequoiaImeTsf.dll` and matching symbols |
| `server_exe` | Windows Server and native panel executables |
| `app_data` | default configuration and runtime resources |
| `app_data/html` | WebView2 UI assets |

Native CMake targets are expected to come from the configured Windows build
directory. The TSF DLL remains an in-process component and the Server remains
out of process; packaging them together does not change that boundary.

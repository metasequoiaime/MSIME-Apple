#pragma once

#include <windows.h>
#include <shlobj.h>
#include <filesystem>
#include <string>
#include <vector>

namespace msime::windows {
// The 32-bit TSF DLL and the 64-bit Server each resolve the state root in their own process, and both must land on the same directory: preferences, dictionaries and runtime leases live there. crates/host-windows `server_state_directory` is a Rust copy of the same order; scripts/test-windows-state-dir-parity.py keeps these names in step with it.
inline constexpr wchar_t state_directory_environment_variable[] = L"METASEQUOIA_IME_DATA_DIR";
inline constexpr wchar_t state_directory_registry_key[] = L"Software\\Metasequoia\\MetasequoiaIME";
inline constexpr wchar_t state_directory_registry_value[] = L"DataDir";
inline constexpr wchar_t state_directory_folder_name[] = L"MSIME-Client";

// An absolute METASEQUOIA_IME_DATA_DIR, then the installer's HKLM DataDir, then %LOCALAPPDATA%\MSIME-Client. Empty only when the known-folder lookup fails.
inline std::filesystem::path resolve_state_directory() {
  // Keep the Windows host relocatable like the upstream installer. The installer/enterprise launcher can provide one absolute data directory; all preferences, dictionaries and runtime leases then follow it instead of silently splitting state between the redirected path and LocalAppData. Read through the process environment block rather than the CRT's copy: the TSF DLL is loaded into arbitrary host processes whose CRT environment may be a stale snapshot, or belong to a different CRT than the one the DLL links.
  {
    std::vector<wchar_t> configured(32768);
    const DWORD length = GetEnvironmentVariableW(
        state_directory_environment_variable, configured.data(),
        static_cast<DWORD>(configured.size()));
    if (length && length < configured.size()) {
      const std::filesystem::path value(std::wstring(configured.data(), length));
      if (value.is_absolute())
        return value;
    }
  }
  // The installer stores its user-selected directory in the 64-bit machine view so the 32-bit TSF DLL and the 64-bit Server resolve the same root. Keep the registry lookup after the environment override for enterprise launches that deliberately inject a temporary profile.
  {
    DWORD bytes = 0;
    if (RegGetValueW(HKEY_LOCAL_MACHINE, state_directory_registry_key,
                     state_directory_registry_value,
                     RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, nullptr,
                     &bytes) == ERROR_SUCCESS &&
        bytes >= sizeof(wchar_t)) {
      std::wstring value(bytes / sizeof(wchar_t), L'\0');
      if (RegGetValueW(HKEY_LOCAL_MACHINE, state_directory_registry_key,
                       state_directory_registry_value,
                       RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr,
                       value.data(), &bytes) == ERROR_SUCCESS) {
        value.resize((bytes / sizeof(wchar_t)) - 1);
        const std::filesystem::path path(value);
        if (path.is_absolute())
          return path;
      }
    }
  }
  PWSTR app_data = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                  &app_data)))
    return {};
  const std::filesystem::path state =
      std::filesystem::path(app_data) / state_directory_folder_name;
  CoTaskMemFree(app_data);
  return state;
}
} // namespace msime::windows

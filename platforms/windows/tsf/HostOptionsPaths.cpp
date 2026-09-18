#include "HostOptionsPaths.h"
#include "HostPathEncoding.h"
#include <windows.h>
#include <shlobj.h>
#include <chrono>
#include <filesystem>
#include <string>

namespace msime::tsf {
PreferenceWatcher::PreferenceWatcher(std::string directory, Published published)
    : directory_(std::move(directory)), published_(std::move(published)),
      worker_(&PreferenceWatcher::run, this) {}
PreferenceWatcher::~PreferenceWatcher() { stop(); }
void PreferenceWatcher::stop() noexcept {
  stopping_.store(true, std::memory_order_release);
  if (worker_.joinable()) worker_.join();
}
void PreferenceWatcher::run() {
  const auto file = std::filesystem::u8path(directory_) / L"runtime-options.json";
  std::filesystem::file_time_type previous{};
  while (!stopping_.load(std::memory_order_acquire)) {
    std::error_code error;
    const auto current = std::filesystem::last_write_time(file, error);
    if (!error && current != previous) {
      previous = current;
      if (published_) {
        try { published_(read_prepared_host_options(file)); } catch (...) {}
      }
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
  }
}
std::string default_state_directory() {
  if (const auto *configured = _wgetenv(L"METASEQUOIA_IME_DATA_DIR");
      configured && *configured) {
    const std::filesystem::path path(configured);
    if (path.is_absolute())
      return path_to_utf8(path);
  }
  constexpr wchar_t key_name[] =
      L"Software\\Metasequoia\\MetasequoiaIME";
  constexpr wchar_t value_name[] = L"DataDir";
  DWORD bytes = 0;
  if (RegGetValueW(HKEY_LOCAL_MACHINE, key_name, value_name,
                   RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr, nullptr,
                   &bytes) == ERROR_SUCCESS && bytes >= sizeof(wchar_t)) {
    std::wstring value(bytes / sizeof(wchar_t), L'\0');
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key_name, value_name,
                     RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY, nullptr,
                     value.data(), &bytes) == ERROR_SUCCESS) {
      value.resize(bytes / sizeof(wchar_t) - 1);
      const std::filesystem::path path(value);
      if (path.is_absolute())
        return path_to_utf8(path);
    }
  }
  PWSTR appData = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &appData))) return {};
  std::filesystem::path state = std::filesystem::path(appData) / L"MSIME-Client";
  CoTaskMemFree(appData);
  return path_to_utf8(state);
}
std::string default_host_options_json() {
  const auto state = default_state_directory();
  return state.empty() ? std::string{} : read_prepared_host_options(std::filesystem::u8path(state) / L"runtime-options.json");
}
}

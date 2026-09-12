#include "HostOptionsPaths.h"
#include <windows.h>
#include <shlobj.h>
#include <chrono>
#include <filesystem>

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
  PWSTR appData = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &appData))) return {};
  std::filesystem::path state = std::filesystem::path(appData) / L"MSIME-Client";
  CoTaskMemFree(appData);
  return state.u8string();
}
std::string default_host_options_json() {
  const auto state = default_state_directory();
  return state.empty() ? std::string{} : read_prepared_host_options(std::filesystem::u8path(state) / L"runtime-options.json");
}
}

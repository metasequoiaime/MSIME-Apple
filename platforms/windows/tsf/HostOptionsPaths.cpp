#include "HostOptionsPaths.h"
#include <windows.h>
#include <shlobj.h>

namespace msime::tsf {
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

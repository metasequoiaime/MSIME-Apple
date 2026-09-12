#include "HostOptionsPaths.h"
#include <windows.h>
#include <shlobj.h>

namespace msime::tsf {
std::string default_host_options_json() {
  PWSTR appData = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &appData))) return {};
  const std::filesystem::path state = std::filesystem::path(appData) / L"MSIME-Client";
  CoTaskMemFree(appData);
  return read_prepared_host_options(state / L"runtime-options.json");
}
}

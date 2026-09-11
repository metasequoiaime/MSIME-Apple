#include "HostOptionsPaths.h"

#include <nlohmann/json.hpp>
#include <windows.h>
#include <shlobj.h>

namespace msime::tsf {

HostOptionsPaths make_host_options_paths(const std::filesystem::path &install_root,
                                         const std::filesystem::path &user_data_root) {
  return {install_root / "share" / "msime", user_data_root,
          user_data_root / "cache", user_data_root / "dictionaries"};
}

std::string host_options_json(const HostOptionsPaths &paths) {
  const auto native = [](const std::filesystem::path &path) { return path.u8string(); };
  return nlohmann::json{{"api_version", 1}, {"resources", native(paths.resources)},
                        {"user_data", native(paths.user_data)}, {"cache", native(paths.cache)},
                        {"dictionaries", native(paths.dictionaries)}}
      .dump();
}

std::string default_host_options_json() {
  wchar_t module[MAX_PATH]{};
  if (!GetModuleFileNameW(nullptr, module, MAX_PATH)) return {};
  std::filesystem::path install_root = std::filesystem::path(module).parent_path().parent_path();
  wchar_t app_data[MAX_PATH]{};
  if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, app_data)))
    return {};
  return host_options_json(make_host_options_paths(
      install_root, std::filesystem::path(app_data) / "MetasequoiaIME"));
}

} // namespace msime::tsf

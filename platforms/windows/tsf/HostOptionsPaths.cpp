#include "HostOptionsPaths.h"

#include <nlohmann/json.hpp>

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

} // namespace msime::tsf

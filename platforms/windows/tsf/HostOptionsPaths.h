#pragma once

#include <filesystem>
#include <string>

namespace msime::tsf {

struct HostOptionsPaths {
  std::filesystem::path resources;
  std::filesystem::path user_data;
  std::filesystem::path cache;
  std::filesystem::path dictionaries;
};

// Build paths from explicit roots; callers remain responsible for validating
// and publishing the resulting HostOptions document.
HostOptionsPaths make_host_options_paths(const std::filesystem::path &install_root,
                                         const std::filesystem::path &user_data_root);
std::string host_options_json(const HostOptionsPaths &paths);

} // namespace msime::tsf

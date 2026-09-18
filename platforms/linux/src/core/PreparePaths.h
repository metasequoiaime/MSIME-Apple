#pragma once

#include <filesystem>
#include <string>

namespace msime_linux {

#ifndef MSIME_INSTALLED_RESOURCE_RELATIVE_DIR
#define MSIME_INSTALLED_RESOURCE_RELATIVE_DIR "../share/msime-client/resources"
#endif

// Resolve the resource bundle installed beside the executable.  The bundle is
// deliberately derived from /proc/self/exe (the caller supplies that resolved
// path), so daemon working directories and PATH lookups cannot change it.
inline std::string installed_resource_directory(
    const std::filesystem::path &executable,
    const std::filesystem::path &relative = MSIME_INSTALLED_RESOURCE_RELATIVE_DIR) {
  if (!executable.is_absolute()) return {};
  if (relative.empty() || relative.is_absolute()) return {};
  const auto candidate =
      (executable.lexically_normal().parent_path() / relative).lexically_normal();
  std::error_code error;
  if (!std::filesystem::is_directory(candidate, error) || error) return {};
  const auto resolved = std::filesystem::canonical(candidate, error);
  if (error || !resolved.is_absolute()) return {};
  return resolved.string();
}

} // namespace msime_linux

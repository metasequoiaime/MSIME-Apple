#pragma once
#include <filesystem>
#include <string>

namespace msime::tsf {
inline std::string path_to_utf8(const std::filesystem::path &path) {
  const auto bytes = path.u8string();
  // C++17 returns string; C++20 returns u8string. The host ABI takes UTF-8
  // bytes in string in either case, never the Windows ANSI code page.
  return {reinterpret_cast<const char *>(bytes.data()), bytes.size()};
}
}

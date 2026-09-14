#pragma once
#include <string_view>

namespace msime::linux_host {
inline constexpr std::string_view default_helpcode_schema(
    std::string_view scheme) {
  return scheme == "shuangpin" ? "lantian" : "ziranma";
}

inline constexpr bool default_show_helpcode(std::string_view scheme) {
  return scheme == "shuangpin";
}
} // namespace msime::linux_host

#pragma once

#include <array>

namespace msime::linux_host {
struct ShuangpinProfileName {
  const char *value;
  const char *label;
};

inline constexpr std::array<ShuangpinProfileName, 4> kShuangpinProfileNames{{
    {"xiaohe", "小鹤"},
    {"ziranma", "自然码"},
    {"shoudao", "首道"},
    {"microsoft", "微软"},
}};
} // namespace msime::linux_host

#pragma once

#include <cstdint>
#include <string_view>

namespace msime::linux_host {

// Keep the built-in accent tokens aligned with the candidate skins used by
// the other native hosts. External skins override this value through the
// validated candidate palette in the shared preferences snapshot.
inline std::uint32_t candidate_builtin_accent(std::string_view skin,
                                              bool dark) {
  if (skin == "wechat") return 0x07C160;
  if (skin == "graphite") return dark ? 0x8993A0 : 0x5F6B7A;
  if (skin == "willow_green") return dark ? 0x65C98D : 0x58B980;
  return 0x6B69D6;
}

} // namespace msime::linux_host

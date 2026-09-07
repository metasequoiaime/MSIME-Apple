#pragma once

#include <map>
#include <string>

namespace metasequoia::apple
{
// Per-key double-pinyin hint text derived from the engine's own profile, so a frontend never
// hardcodes a keymap that can drift from the scheme the session actually runs.
//
// The key is an uppercase letter. The value reads "initials / finals" when a key carries both,
// otherwise whichever side it carries; a key that carries neither is absent from the map.
std::map<std::string, std::string> shuangpin_key_hints(bool uses_shuangpin, const std::string &profile_name = "xiaohe");
} // namespace metasequoia::apple

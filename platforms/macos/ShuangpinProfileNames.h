#pragma once
#include <string_view>
namespace metasequoia::mac {
inline const char *NormalizeShuangpinSchema(std::string_view name) {
    for (const char *identifier : {"xiaohe", "ziranma", "shoudao", "microsoft"}) {
        if (name == identifier) return identifier;
    }
    return "xiaohe";
}
inline const char *ShuangpinSchemaTitle(std::string_view name) {
    const std::string_view identifier = NormalizeShuangpinSchema(name);
    if (identifier == "ziranma") return "自然码双拼";
    if (identifier == "shoudao") return "首道双拼";
    if (identifier == "microsoft") return "微软双拼";
    return "小鹤双拼";
}
}

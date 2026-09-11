#pragma once

#include "core/scheme_type.h"

#include <array>
#include <string_view>

namespace metasequoia::mac
{
constexpr int NormalizeStoredInputScheme(int scheme)
{
    return scheme >= 0 && scheme <= 2 ? scheme : 0;
}

constexpr SchemeType EngineSchemeForStoredPreference(int scheme)
{
    switch (NormalizeStoredInputScheme(scheme))
    {
    case 1:
        return SchemeType::Shuangpin;
    case 2:
        return SchemeType::Wubi;
    default:
        return SchemeType::Quanpin;
    }
}

inline constexpr std::array<const char *, 4> kShuangpinSchemaIdentifiers = {"xiaohe", "ziranma", "shoudao",
                                                                            "microsoft"};

inline const char *NormalizeShuangpinSchema(std::string_view name)
{
    for (const char *identifier : kShuangpinSchemaIdentifiers)
    {
        if (name == identifier)
        {
            return identifier;
        }
    }
    return kShuangpinSchemaIdentifiers.front();
}

inline const char *ShuangpinSchemaTitle(std::string_view name)
{
    const std::string_view identifier = NormalizeShuangpinSchema(name);
    if (identifier == "ziranma")
    {
        return "自然码双拼";
    }
    if (identifier == "shoudao")
    {
        return "首道双拼";
    }
    if (identifier == "microsoft")
    {
        return "微软双拼";
    }
    return "小鹤双拼";
}

inline bool ShouldRouteSemicolonAsShuangpinInput(SchemeType scheme, std::string_view profile)
{
    return scheme == SchemeType::Shuangpin && profile == "microsoft";
}
} // namespace metasequoia::mac

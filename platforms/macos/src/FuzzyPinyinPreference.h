#pragma once

#include <metasequoia/session.h>
#include <array>

namespace metasequoia::mac
{
struct FuzzyPinyinChoice
{
    const char *title;
    FuzzyPinyinRule rule;
};
inline constexpr std::array<FuzzyPinyinChoice, 11> FuzzyPinyinChoices = {{
    {"z ↔ zh", FuzzyPinyinRule::Z_ZH}, {"c ↔ ch", FuzzyPinyinRule::C_CH},
    {"s ↔ sh", FuzzyPinyinRule::S_SH}, {"n ↔ l", FuzzyPinyinRule::N_L},
    {"f ↔ h", FuzzyPinyinRule::F_H}, {"r ↔ l", FuzzyPinyinRule::R_L},
    {"an ↔ ang", FuzzyPinyinRule::AN_ANG}, {"en ↔ eng", FuzzyPinyinRule::EN_ENG},
    {"in ↔ ing", FuzzyPinyinRule::IN_ING}, {"ian ↔ iang", FuzzyPinyinRule::IAN_IANG},
    {"uan ↔ uang", FuzzyPinyinRule::UAN_UANG},
}};
inline constexpr std::uint32_t FuzzyPinyinMask()
{
    std::uint32_t mask = 0;
    for (const auto &choice : FuzzyPinyinChoices)
        mask |= static_cast<std::uint32_t>(choice.rule);
    return mask;
}
}

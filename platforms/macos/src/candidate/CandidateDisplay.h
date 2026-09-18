#pragma once

#include "common/helpcode_utils.h"
#include <metasequoia/session.h>
#include "core/scheme_type.h"
#include "core/word_item.h"
#include <string>

namespace metasequoia::mac {
inline bool HelpcodesAnnotateLocalMode(LocalInputMode mode)
{
    return mode == LocalInputMode::None || mode == LocalInputMode::SuperJianpin;
}

inline bool ScriptConversionAppliesToLocalMode(LocalInputMode mode)
{
    return mode != LocalInputMode::Unicode;
}

inline std::string CandidateDisplayText(const WordItem &candidate, SchemeType scheme, bool helpcodeEnabled,
                                        const HelpcodeUtils::Keymap *keymap = nullptr)
{
    if (!helpcodeEnabled || keymap == nullptr || (scheme != SchemeType::Quanpin && scheme != SchemeType::Shuangpin)) {
        return candidate.word;
    }
    return candidate.word + HelpcodeUtils::compute_helpcodes(candidate.word, false, keymap);
}
} // namespace metasequoia::mac

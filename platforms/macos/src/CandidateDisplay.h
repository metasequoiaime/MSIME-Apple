#pragma once

#include "common/helpcode_utils.h"
#include <metasequoia/session.h>
#include "core/scheme_type.h"
#include "core/word_item.h"

#include <string>

namespace metasequoia::mac
{
// A helpcode says how to reach a word through pinyin. A local input mode that synthesises its
// candidates has no such word to annotate: a date, a code point, a quick phrase or a kaomoji was
// never typed in pinyin, and compute_helpcodes still finds Han characters in "2026年9月6日" and
// appends the letters for 年 and 日 to it. Super jianpin is the exception — it is pinyin initials
// over the same dictionary, so its candidates are ordinary words with real helpcodes.
inline bool HelpcodesAnnotateLocalMode(LocalInputMode mode)
{
    return mode == LocalInputMode::None || mode == LocalInputMode::SuperJianpin;
}

// Traditional output rewrites the script of a Chinese candidate, which is a choice about how to
// render a word. A Unicode code point is not that: the user named one exact character, and handing
// back its traditional counterpart is handing back a different character than the one requested.
inline bool ScriptConversionAppliesToLocalMode(LocalInputMode mode)
{
    return mode != LocalInputMode::Unicode;
}

inline std::string CandidateDisplayText(const WordItem &candidate, SchemeType scheme, bool helpcodeEnabled,
                                        const HelpcodeUtils::Keymap *keymap = nullptr)
{
    if (!helpcodeEnabled || keymap == nullptr || (scheme != SchemeType::Quanpin && scheme != SchemeType::Shuangpin))
    {
        return candidate.word;
    }
    return candidate.word + HelpcodeUtils::compute_helpcodes(candidate.word, false, keymap);
}
} // namespace metasequoia::mac

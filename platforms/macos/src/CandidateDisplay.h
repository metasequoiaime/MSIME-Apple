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

// What is still to be typed to reach this candidate on its own. A wubi candidate carries the code
// it was found by, and an unfinished code answers with the codes it can still become, so the tail
// of each candidate's code is the keystrokes that single it out. The candidate typed in full has no
// tail and gets no hint, and a code that is not an extension of what was typed -- a word the pinyin
// fallback answered with, a user entry keyed differently -- gets none either, since its letters
// would not take the user there.
inline std::string WubiCodeHint(const WordItem &candidate, const std::string &typedCode)
{
    if (typedCode.empty() || candidate.pinyin.size() <= typedCode.size() ||
        candidate.pinyin.compare(0, typedCode.size(), typedCode) != 0)
    {
        return {};
    }
    return candidate.pinyin.substr(typedCode.size());
}

// typedCode is the wubi code already entered, and is left empty wherever a code hint does not
// apply: any other scheme, the hint switched off, or a composition the pinyin fallback answered.
inline std::string CandidateDisplayText(const WordItem &candidate, SchemeType scheme, bool helpcodeEnabled,
                                        const HelpcodeUtils::Keymap *keymap = nullptr,
                                        const std::string &typedCode = {})
{
    if (scheme == SchemeType::Wubi)
    {
        const auto hint = WubiCodeHint(candidate, typedCode);
        // A space, not the bare append the helpcodes use: a wubi code is the same run of latin
        // letters as the one in the preedit, and 爷b reads as one word rather than a word and the
        // keys that finish it.
        return hint.empty() ? candidate.word : candidate.word + " " + hint;
    }
    if (!helpcodeEnabled || keymap == nullptr || (scheme != SchemeType::Quanpin && scheme != SchemeType::Shuangpin))
    {
        return candidate.word;
    }
    return candidate.word + HelpcodeUtils::compute_helpcodes(candidate.word, false, keymap);
}
} // namespace metasequoia::mac

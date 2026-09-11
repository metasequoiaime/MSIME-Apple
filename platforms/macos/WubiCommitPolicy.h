#pragma once

#include <metasequoia/session.h>

#include <cstddef>

namespace metasequoia::mac
{
inline bool ShouldAutoCommitUniqueWubiCandidate(bool enabled, SchemeType scheme, std::size_t codeLength,
                                                std::size_t candidateCount, bool answeredByPinyinFallback)
{
    // A code answered by the mixed-pinyin fallback is not a unique four-code wubi candidate, however
    // much it looks like one. Committing it would take away the fifth letter the fallback exists to
    // allow, which is the whole point for spellings like nihao, women and zhongguo.
    return enabled && scheme == SchemeType::Wubi && !answeredByPinyinFallback && codeLength == 4 && candidateCount == 1;
}

inline KeyResult HandleCharacterWithWubiAutoCommit(Session &session, char character, bool enabled)
{
    KeyResult result = session.character(character);
    const auto snapshot = session.snapshot();
    if (result.handled &&
        ShouldAutoCommitUniqueWubiCandidate(enabled, snapshot.scheme, snapshot.preedit.size(),
                                            snapshot.candidates.size(), snapshot.answered_by_pinyin_fallback))
    {
        result = session.command(Command::CommitCandidate);
    }
    return result;
}
} // namespace metasequoia::mac

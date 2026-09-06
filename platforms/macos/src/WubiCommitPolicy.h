#pragma once

#include <metasequoia/session.h>

#include <cstddef>

namespace metasequoia::mac
{
inline bool ShouldAutoCommitUniqueWubiCandidate(bool enabled, SchemeType scheme, std::size_t codeLength,
                                                std::size_t candidateCount)
{
    return enabled && scheme == SchemeType::Wubi && codeLength == 4 && candidateCount == 1;
}

inline KeyResult HandleCharacterWithWubiAutoCommit(Session &session, char character, bool enabled)
{
    KeyResult result = session.character(character);
    const auto snapshot = session.snapshot();
    if (result.handled &&
        ShouldAutoCommitUniqueWubiCandidate(enabled, snapshot.scheme, snapshot.preedit.size(),
                                            snapshot.candidates.size()))
    {
        result = session.command(Command::CommitCandidate);
    }
    return result;
}
} // namespace metasequoia::mac

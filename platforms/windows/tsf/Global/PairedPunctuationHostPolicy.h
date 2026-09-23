#pragma once
#include <string_view>

namespace Global
{
// Match the executable basename, independently of the user's locale. Excel's
// cell editor interprets the completion's left arrow as cell navigation.
inline bool IsPairedPunctuationExcludedProcess(std::wstring_view processName)
{
    constexpr std::wstring_view excluded = L"excel.exe";
    if (processName.size() != excluded.size())
        return false;
    for (size_t i = 0; i < excluded.size(); ++i)
    {
        const wchar_t c = processName[i];
        const wchar_t lower = c >= L'A' && c <= L'Z' ? c + (L'a' - L'A') : c;
        if (lower != excluded[i])
            return false;
    }
    return true;
}

// The closing half the pressed key would step over, or 0 when the key cannot close a tracked pair. Only the closing half of a pair the host auto-completes qualifies (the '{' pair included, whose table entry is ASCII); ASCII output such as direct-mode ',' '.' ':' or the numpad dot and unrelated Chinese marks ('。' '：' '；' ...) must answer 0, because stepping over clears the whole pair stack on a mismatch and would silently drop the pair the user is still inside. Quotes are keyed symmetrically: '"' resolves to either half depending on the legacy left/right toggle, so the resolved character says nothing about intent and the key itself has to answer.
inline wchar_t PairedPunctuationStepOverCandidate(wchar_t key, std::wstring_view resolved)
{
    if (resolved.size() != 1)
        return 0;
    if (key == L'"')
        return L'”';
    if (key == L'\'')
        return L'’';
    switch (resolved[0])
    {
    case L'”':
    case L'’':
    case L'】':
    case L'》':
    case L'〉':
    case L'）':
    case L'}':
        return resolved[0];
    default:
        return 0;
    }
}
} // namespace Global

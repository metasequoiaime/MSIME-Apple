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
} // namespace Global

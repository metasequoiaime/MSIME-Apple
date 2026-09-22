#pragma once

#include <cstddef>
#include <string>

inline bool ParseCommitCandidateAndContinuePayload(const std::wstring &payload,
                                                   std::size_t &consumed,
                                                   std::wstring &text)
{
    const std::size_t tab = payload.find(L'\t');
    if (tab == std::wstring::npos || tab == 0)
    {
        return false;
    }
    constexpr std::size_t maximumConsumed = 1u << 20;
    std::size_t parsed = 0;
    for (std::size_t index = 0; index < tab; ++index)
    {
        const wchar_t value = payload[index];
        if (value < L'0' || value > L'9')
        {
            return false;
        }
        parsed = parsed * 10 + static_cast<std::size_t>(value - L'0');
        if (parsed > maximumConsumed)
        {
            return false;
        }
    }
    consumed = parsed;
    text = payload.substr(tab + 1);
    return true;
}

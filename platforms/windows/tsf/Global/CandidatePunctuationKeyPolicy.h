#pragma once

namespace Global
{
// Win32 virtual-key codes, spelled out so this header stays free of <Windows.h> and its tests run on any host.
inline constexpr unsigned VirtualKeyTab = 0x09;
inline constexpr unsigned VirtualKeyPrior = 0x21;
inline constexpr unsigned VirtualKeyNext = 0x22;
inline constexpr unsigned VirtualKeyEnd = 0x23;
inline constexpr unsigned VirtualKeyHome = 0x24;
inline constexpr unsigned VirtualKeyNumpadAdd = 0x6B;
inline constexpr unsigned VirtualKeyNumpadSubtract = 0x6D;
inline constexpr unsigned VirtualKeyNumpadDecimal = 0x6E;
inline constexpr unsigned VirtualKeyNumpadDivide = 0x6F;
inline constexpr unsigned VirtualKeyOemPlus = 0xBB;
inline constexpr unsigned VirtualKeyOemMinus = 0xBD;

// Keys that keep their candidate navigation meaning while candidates are open, even when the character they carry is listed in CommitWithHighlightedCandPunc. The numpad '+' and '-' are deliberately absent: they are arithmetic keys, not paging keys, so they commit the highlighted candidate like any other punctuation (reference 1d2431ad).
inline bool IsCandidateNavigationKeyBeforePunctuation(unsigned code)
{
    switch (code)
    {
    case VirtualKeyPrior:
    case VirtualKeyNext:
    case VirtualKeyOemMinus:
    case VirtualKeyOemPlus:
    case VirtualKeyHome:
    case VirtualKeyEnd:
    case VirtualKeyTab:
        return true;
    default:
        return false;
    }
}

// The ASCII character that follows the highlighted candidate when this key commits it, or 0 when the key's punctuation is translated as usual. The numpad arithmetic keys and '/' stay literal, and the numpad decimal is always '.' whatever the keyboard layout reports for it, so typing an expression or a path right after a candidate does not turn into Chinese punctuation.
inline wchar_t LiteralCandidatePunctuation(unsigned code, wchar_t wch)
{
    switch (code)
    {
    case VirtualKeyNumpadDecimal:
        return L'.';
    case VirtualKeyNumpadAdd:
        return L'+';
    case VirtualKeyNumpadSubtract:
        return L'-';
    case VirtualKeyNumpadDivide:
        return L'/';
    default:
        return wch == L'/' ? L'/' : 0;
    }
}
} // namespace Global

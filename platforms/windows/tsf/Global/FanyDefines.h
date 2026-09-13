#pragma once
#include <string>
#include <string_view>
#include <unordered_set>
#include <Windows.h>

namespace Global
{
inline std::wstring ZEN_BROWSER = L"zen.exe";
// Some hosts cannot correctly consume the caret move used by paired
// punctuation. Keep this policy at the TSF host boundary so the key handler
// can fall back to its ordinary punctuation behavior for those processes.
inline const wchar_t *const PAIRED_PUNCTUATION_EXCLUDED_APPS[] = {L"EXCEL.EXE"};

inline bool IsPairedPunctuationExcludedProcess(const std::wstring &processName)
{
    if (processName.empty())
    {
        return false;
    }
    for (const wchar_t *excluded : PAIRED_PUNCTUATION_EXCLUDED_APPS)
    {
        if (CompareStringOrdinal(processName.c_str(), -1, excluded, -1, TRUE) == CSTR_EQUAL)
        {
            return true;
        }
    }
    return false;
}
// inline std::unordered_set<std::wstring> VSCodeSeries = {L"Code.exe", L"Code - Insiders.exe", L"VSCodium.exe"};
// inline bool IsVSCodeLike = false;
inline LONG INVALID_Y = -100000;
} // namespace Global

namespace GlobalSettings
{
//
// 支持的 TSF 预编辑格式
//  - raw: 原始按键序列
//  - pinyin: 分词后的拼音序列
//  - empty: 行内不显示预编辑
//  - cand: 当前高亮的候选词序列（预留）
//
namespace TsfPreeditStyle
{
constexpr std::string_view Raw = "raw";
constexpr std::string_view Pinyin = "pinyin";
constexpr std::string_view Empty = "empty";
constexpr std::string_view Cand = "cand";
} // namespace TsfPreeditStyle

inline bool isKnownTsfPreeditStyle(std::string_view style)
{
    return style == TsfPreeditStyle::Raw || style == TsfPreeditStyle::Pinyin || style == TsfPreeditStyle::Empty;
}

inline std::string normalizeTsfPreeditStyle(std::string_view style)
{
    if (style == TsfPreeditStyle::Pinyin || style == TsfPreeditStyle::Empty)
    {
        return std::string(style);
    }
    return std::string(TsfPreeditStyle::Raw);
}

inline std::string &tsfPreeditStyleStorage()
{
    static std::string style = std::string(TsfPreeditStyle::Raw); // 默认的原始按键序列
    return style;
}

inline const std::string &getTsfPreeditStyle()
{
    return tsfPreeditStyleStorage();
}

inline void setTsfPreeditStyle(std::string_view newStyle)
{
    tsfPreeditStyleStorage() = normalizeTsfPreeditStyle(newStyle);
}

inline void setTsfPreeditStyleFromWide(const wchar_t *style)
{
    if (!style)
    {
        setTsfPreeditStyle(TsfPreeditStyle::Raw);
        return;
    }
    if (wcscmp(style, L"pinyin") == 0)
    {
        setTsfPreeditStyle(TsfPreeditStyle::Pinyin);
    }
    else if (wcscmp(style, L"empty") == 0)
    {
        setTsfPreeditStyle(TsfPreeditStyle::Empty);
    }
    else
    {
        setTsfPreeditStyle(TsfPreeditStyle::Raw);
    }
}

inline bool isKnownTsfPreeditStyleWide(const wchar_t *style)
{
    return style && (wcscmp(style, L"raw") == 0 || wcscmp(style, L"pinyin") == 0 || wcscmp(style, L"empty") == 0);
}
} // namespace GlobalSettings

namespace GlobalIme
{
extern thread_local std::wstring word_for_creating_word;
// One-shot override for TSF inline preedit after NeedToCreateWord (pinyin mode).
// Consumed by _HandleCompositionInputWorker, then cleared.
extern thread_local std::wstring pending_create_word_preedit;
} // namespace GlobalIme

namespace Global
{
inline thread_local HWND msgWndHandle = nullptr;
}

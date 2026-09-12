#pragma once

#include <Carbon/Carbon.h>

#include <algorithm>
#include <cstddef>

namespace metasequoia::mac
{
enum class ControllerKeyAction
{
    Character,
    MoveCandidateLeft,
    MoveCandidateRight,
    MoveCandidateUp,
    MoveCandidateDown,
    MoveCandidatePageUp,
    MoveCandidatePageDown,
    MoveCandidateHome,
    MoveCandidateEnd,
    Backspace,
    CommitRaw,
    Cancel,
    CommitCandidate,
    CommitFirstHan,
    CommitLastHan,
};

struct CandidateKeyOptions
{
    bool minusEqual = true;
    bool commaPeriod = false;
    bool brackets = false;
    bool pageKeys = true;
    bool verticalNavigation = true;
    bool edgeSelection = false;
};

enum class CandidatePageShortcut
{
    MinusEqual = 0,
    Brackets = 1,
    PageKeys = 2,
};

constexpr CandidatePageShortcut NormalizeCandidatePageShortcut(int value)
{
    switch (value)
    {
    case 1:
        return CandidatePageShortcut::Brackets;
    case 2:
        return CandidatePageShortcut::PageKeys;
    default:
        return CandidatePageShortcut::MinusEqual;
    }
}

constexpr size_t CandidatePageStart(size_t selectedIndex, size_t candidateCount, size_t pageSize)
{
    if (candidateCount == 0 || pageSize == 0)
    {
        return 0;
    }
    return std::min(selectedIndex, candidateCount - 1) / pageSize * pageSize;
}

constexpr size_t CandidatePageEnd(size_t selectedIndex, size_t candidateCount, size_t pageSize)
{
    if (candidateCount == 0 || pageSize == 0)
    {
        return 0;
    }
    return std::min(CandidatePageStart(selectedIndex, candidateCount, pageSize) + pageSize - 1, candidateCount - 1);
}

constexpr ControllerKeyAction ClassifyControllerKey(
    unsigned short keyCode, bool candidatePanelVisible,
    CandidatePageShortcut pageShortcut = CandidatePageShortcut::MinusEqual, char pageShortcutCharacter = '\0',
    bool pageShortcutModified = false)
{
    if (candidatePanelVisible)
    {
        switch (keyCode)
        {
        case kVK_LeftArrow:
            return ControllerKeyAction::MoveCandidateLeft;
        case kVK_RightArrow:
            return ControllerKeyAction::MoveCandidateRight;
        case kVK_UpArrow:
            return ControllerKeyAction::MoveCandidateUp;
        case kVK_DownArrow:
            return ControllerKeyAction::MoveCandidateDown;
        case kVK_PageUp:
            return ControllerKeyAction::MoveCandidatePageUp;
        case kVK_PageDown:
            return ControllerKeyAction::MoveCandidatePageDown;
        case kVK_Home:
            return ControllerKeyAction::MoveCandidateHome;
        case kVK_End:
            return ControllerKeyAction::MoveCandidateEnd;
        default:
            break;
        }

        if (!pageShortcutModified)
        {
            if ((pageShortcut == CandidatePageShortcut::MinusEqual && pageShortcutCharacter == '-') ||
                (pageShortcut == CandidatePageShortcut::Brackets && pageShortcutCharacter == '['))
            {
                return ControllerKeyAction::MoveCandidatePageUp;
            }
            if ((pageShortcut == CandidatePageShortcut::MinusEqual && pageShortcutCharacter == '=') ||
                (pageShortcut == CandidatePageShortcut::Brackets && pageShortcutCharacter == ']'))
            {
                return ControllerKeyAction::MoveCandidatePageDown;
            }
        }
    }

    switch (keyCode)
    {
    case kVK_Delete:
        return ControllerKeyAction::Backspace;
    case kVK_Return:
    case kVK_ANSI_KeypadEnter:
        return ControllerKeyAction::CommitRaw;
    case kVK_Escape:
        return ControllerKeyAction::Cancel;
    case kVK_Space:
        return ControllerKeyAction::CommitCandidate;
    default:
        return ControllerKeyAction::Character;
    }
}
constexpr ControllerKeyAction ClassifyConfiguredControllerKey(unsigned short keyCode, bool visible,
                                                              CandidateKeyOptions options, char character,
                                                              bool modified)
{
    if (visible && !modified)
    {
        if (options.edgeSelection && character == '[')
            return ControllerKeyAction::CommitFirstHan;
        if (options.edgeSelection && character == ']')
            return ControllerKeyAction::CommitLastHan;
        if ((options.minusEqual && character == '-') || (options.commaPeriod && character == ',') ||
            (options.brackets && !options.edgeSelection && character == '['))
            return ControllerKeyAction::MoveCandidatePageUp;
        if ((options.minusEqual && character == '=') || (options.commaPeriod && character == '.') ||
            (options.brackets && !options.edgeSelection && character == ']'))
            return ControllerKeyAction::MoveCandidatePageDown;
    }
    if ((keyCode == kVK_PageUp || keyCode == kVK_PageDown) && (!options.pageKeys || modified))
        return ControllerKeyAction::Character;
    if ((keyCode == kVK_UpArrow || keyCode == kVK_DownArrow) && !options.verticalNavigation)
        return ControllerKeyAction::Character;
    return ClassifyControllerKey(keyCode, visible, CandidatePageShortcut::PageKeys, '\0', modified);
}
} // namespace metasequoia::mac

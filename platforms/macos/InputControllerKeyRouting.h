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

// Main-row ANSI digit key codes.  Reading event.characters is layout
// dependent (for example, Dvorak and IME layouts can produce non-digits),
// while candidate numbering follows the physical number row on Windows.
constexpr int PhysicalCandidateDigitSlot(unsigned short keyCode)
{
    switch (keyCode)
    {
    case 18: return 0; // 1
    case 19: return 1; // 2
    case 20: return 2; // 3
    case 21: return 3; // 4
    case 23: return 4; // 5
    case 22: return 5; // 6
    case 26: return 6; // 7
    case 28: return 7; // 8
    case 25: return 8; // 9
    default: return -1;
    }
}

// Japanese input schemes reserve '-' and '=' for Engine input while a
// candidate list is visible.  The direct Japanese scheme (3) and the
// temporary-Japanese local mode share this host rule; other schemes use the
// configured paging shortcuts.
constexpr bool IsJapaneseMinusEqualInput(int scheme, bool temporaryJapanese, char character)
{
    return (scheme == 3 || temporaryJapanese) && (character == '-' || character == '=');
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
} // namespace metasequoia::mac

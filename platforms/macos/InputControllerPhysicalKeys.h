#pragma once

namespace msime::mac
{
// Main-row ANSI digit key codes used for candidate selection.  These helpers
// live in the Engine-facing namespace so InputController.mm can include them
// alongside CandidateSkin.h, which reserves metasequoia::mac as an alias.
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

constexpr bool IsJapaneseMinusEqualInput(int scheme, bool temporaryJapanese, char character)
{
    return (scheme == 3 || temporaryJapanese) && (character == '-' || character == '=');
}
} // namespace msime::mac

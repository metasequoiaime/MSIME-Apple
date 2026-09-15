#pragma once

namespace msime::mac
{
enum class MaintenanceShortcutAction
{
    None,
    ClearCache,
    Restart,
    Terminate,
};

// InputMethodKit only receives events for the active input context.  Preserve
// the Windows maintenance keys while replacing Alt with macOS Option and using
// physical ANSI key codes so keyboard-layout characters cannot change them.
constexpr MaintenanceShortcutAction PhysicalMaintenanceShortcut(unsigned short keyCode, bool control, bool shift,
                                                                  bool option, bool command)
{
    if (!control || !shift || !option || command)
        return MaintenanceShortcutAction::None;
    switch (keyCode)
    {
    case 8: return MaintenanceShortcutAction::ClearCache; // C
    case 15: return MaintenanceShortcutAction::Restart;   // R
    case 17: return MaintenanceShortcutAction::Terminate; // T
    default: return MaintenanceShortcutAction::None;
    }
}

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
    // AppKit reports the physical ANSI keypad digits separately from the
    // number row. Windows normalizes VK_NUMPAD1..9 before candidate routing;
    // keep the same selection contract on macOS without accepting keypad 0.
    case 83: return 0; // kVK_ANSI_Keypad1
    case 84: return 1; // kVK_ANSI_Keypad2
    case 85: return 2; // kVK_ANSI_Keypad3
    case 86: return 3; // kVK_ANSI_Keypad4
    case 87: return 4; // kVK_ANSI_Keypad5
    case 88: return 5; // kVK_ANSI_Keypad6
    case 89: return 6; // kVK_ANSI_Keypad7
    case 91: return 7; // kVK_ANSI_Keypad8
    case 92: return 8; // kVK_ANSI_Keypad9
    default: return -1;
    }
}

constexpr bool IsJapaneseMinusEqualInput(int scheme, bool temporaryJapanese, char character)
{
    return (scheme == 3 || temporaryJapanese) && (character == '-' || character == '=');
}
} // namespace msime::mac

#pragma once

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

namespace metasequoia::mac
{
inline bool IsInputModeToggle(unsigned short keyCode, NSEventModifierFlags modifiers)
{
    const NSEventModifierFlags competingModifiers =
        modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
    return keyCode == kVK_Space && (modifiers & NSEventModifierFlagShift) != 0 && competingModifiers == 0;
}

inline bool ShouldToggleInputMode(bool shortcutEnabled, unsigned short keyCode, NSEventModifierFlags modifiers)
{
    return shortcutEnabled && IsInputModeToggle(keyCode, modifiers);
}

inline bool ShouldPrepareInputSession(bool /* englishMode */)
{
    // Both Chinese composition and English completion use an Engine session.
    return true;
}
} // namespace metasequoia::mac

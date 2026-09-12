#pragma once

// From MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

namespace msime::mac
{
inline bool IsFullWidthInputToggle(unsigned short keyCode, NSEventModifierFlags modifiers)
{
    const NSEventModifierFlags allModifiers = NSEventModifierFlagCommand | NSEventModifierFlagControl |
        NSEventModifierFlagOption | NSEventModifierFlagShift;
    if (keyCode == kVK_Space && (modifiers & allModifiers) == (NSEventModifierFlagControl | NSEventModifierFlagShift)) return true;
    const NSEventModifierFlags competingModifiers =
        modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl);
    return keyCode == kVK_ANSI_H && (modifiers & NSEventModifierFlagOption) != 0 &&
           (modifiers & NSEventModifierFlagShift) != 0 && competingModifiers == 0;
}

inline bool IsFullWidthConvertibleCharacter(unichar character)
{
    return character == ' ' || (character >= '!' && character <= '~');
}

inline bool IsFullWidthDirectCharacter(unichar character, NSEventModifierFlags modifiers)
{
    const NSEventModifierFlags competingModifiers =
        modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
    return competingModifiers == 0 && IsFullWidthConvertibleCharacter(character);
}

inline unichar FullWidthCharacter(unichar character)
{
    return character == ' ' ? 0x3000 : static_cast<unichar>(character + 0xFEE0);
}
} // namespace msime::mac

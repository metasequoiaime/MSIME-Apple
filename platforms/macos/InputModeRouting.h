#pragma once

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

namespace msime::mac
{
inline bool IsInputModeToggle(unsigned short keyCode, NSEventModifierFlags modifiers)
{
    const NSEventModifierFlags competingModifiers =
        modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
    return keyCode == kVK_Space && (modifiers & NSEventModifierFlagShift) != 0 && competingModifiers == 0;
}
} // namespace msime::mac

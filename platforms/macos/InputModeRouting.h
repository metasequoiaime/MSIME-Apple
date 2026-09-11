#pragma once
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
namespace metasequoia::mac {
inline bool IsInputModeToggle(unsigned short keyCode, NSEventModifierFlags modifiers) {
    const auto competing = modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
    return keyCode == kVK_Space && (modifiers & NSEventModifierFlagShift) != 0 && competing == 0;
}
inline bool ShouldToggleInputMode(bool enabled, unsigned short keyCode, NSEventModifierFlags modifiers) {
    return enabled && IsInputModeToggle(keyCode, modifiers);
}
inline bool ShouldPrepareInputSession(bool englishMode) { return !englishMode; }
}

#pragma once
#import <AppKit/AppKit.h>
#include <cmath>
#include <set>

// Observe the complete key stream; only a short, isolated modifier release toggles.
// Engine composition remains owned by the normal host mode-switch operation.
class MSIMEModifierTap {
public:
    void reset() { *this = MSIMEModifierTap{}; }
    bool observe(NSEvent *event, bool shiftEnabled, bool controlEnabled) {
        const auto mask = NSEventModifierFlagShift | NSEventModifierFlagControl |
            NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagFunction;
        const auto flags = event.modifierFlags & mask;
        const auto previous = modifiers_;
        modifiers_ = flags;
        if (event.type == NSEventTypeKeyDown) {
            keys_.insert(event.keyCode);
            armed_ = false;
            return false;
        }
        if (event.type == NSEventTypeKeyUp) {
            keys_.erase(event.keyCode);
            armed_ = false;
            return false;
        }
        if (event.type != NSEventTypeFlagsChanged) return false;
        const bool shift = event.keyCode == 56 || event.keyCode == 60;
        const bool control = event.keyCode == 59 || event.keyCode == 62;
        const bool enabled = (shift && shiftEnabled) || (control && controlEnabled);
        const auto required = shift ? NSEventModifierFlagShift : NSEventModifierFlagControl;
        const double time = event.timestamp;
        const bool sameModifier = (shift || control) && required == armedModifier_;
        const bool toggle = armed_ && sameModifier && flags == 0 &&
            previous == required && enabled && keys_.empty() && std::isfinite(time) &&
            time >= pressedAt_ && time - pressedAt_ < 0.5;
        // Both sides of the same modifier form one tap, timed from the first
        // press and completed only when the last side is released.
        if (armed_ && sameModifier && flags == required && enabled) return false;
        armed_ = false;
        // No rearming while another modifier is held. Chords and interrupted
        // taps remain cancelled even after the competing modifier is released.
        if (enabled && previous == 0 && flags == required && keys_.empty() && std::isfinite(time)) {
            armed_ = true;
            armedModifier_ = required;
            pressedAt_ = time;
        }
        return toggle;
    }
private:
    std::set<unsigned short> keys_;
    NSEventModifierFlags modifiers_ = 0;
    NSEventModifierFlags armedModifier_ = 0;
    double pressedAt_ = 0;
    bool armed_ = false;
};

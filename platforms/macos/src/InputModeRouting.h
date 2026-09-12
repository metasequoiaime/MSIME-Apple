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

// A Shift held longer than this is being used for something else -- selecting text with the mouse,
// holding a capital -- and must not switch anyone's input mode out from under them. Nothing else in
// the keyboard needs a timer; this one exists because Shift alone is also half of every other Shift
// gesture, and a release is the only moment at which the two can still be told apart.
inline constexpr double kSolitaryShiftInterval = 0.5;

// Shift pressed and released with nothing in between. The press cannot decide anything on its own --
// Shift+A starts exactly the same way -- so the press only arms this and the release fires it, and
// any key or competing modifier arriving first disarms it.
class SolitaryShiftTracker
{
  public:
    // Feed every flags-changed event here. Returns true when this release completed a solitary tap.
    bool flagsChanged(NSEventModifierFlags modifiers, double timestamp)
    {
        const bool shiftDown = (modifiers & NSEventModifierFlagShift) != 0;
        const bool competing =
            (modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0;
        if (shiftDown)
        {
            if (competing)
            {
                armed_ = false;
            }
            else if (!armed_)
            {
                armed_ = true;
                pressedAt_ = timestamp;
            }
            return false;
        }
        const bool fired = armed_ && !competing && (timestamp - pressedAt_) <= kSolitaryShiftInterval;
        armed_ = false;
        return fired;
    }

    // Any key pressed while Shift is down makes this a Shift+key gesture rather than a tap.
    void keyDown()
    {
        armed_ = false;
    }

    void reset()
    {
        armed_ = false;
    }

  private:
    bool armed_ = false;
    double pressedAt_ = 0;
};

// A tap during a composition ends it as the letters that were typed, rather than switching modes:
// it is how a word the dictionary does not carry -- a name, a command, an acronym -- gets out in
// the middle of Chinese input without losing what was already typed. With nothing composing there
// is nothing to convert, so the tap means the mode switch. Both sides answer to the one preference,
// since someone who turned the shortcut off wants Shift left alone.
enum class SolitaryShiftAction
{
    Ignore,
    CommitComposition,
    ToggleInputMode,
};

inline SolitaryShiftAction ActionForSolitaryShift(bool shortcutEnabled, bool composing)
{
    if (!shortcutEnabled)
    {
        return SolitaryShiftAction::Ignore;
    }
    return composing ? SolitaryShiftAction::CommitComposition : SolitaryShiftAction::ToggleInputMode;
}

inline bool ShouldPrepareInputSession(bool englishMode)
{
    return !englishMode;
}
} // namespace metasequoia::mac

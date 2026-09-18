#pragma once

#include <sys/types.h>

namespace msime::mac {

/// Keep an external foreground process as the screen-keyboard target.
/// The input method itself and invalid PIDs are never valid destinations.
inline pid_t CapturedScreenKeyboardTarget(pid_t candidate, pid_t ownProcess) {
    if (candidate <= 0 || candidate == ownProcess) return 0;
    return candidate;
}

/// Resolve the destination sampled immediately before a screen-keyboard stroke.
/// Keeping this policy separate makes the live-foreground rule testable without
/// creating or posting a CoreGraphics event.
inline pid_t LiveScreenKeyboardTarget(pid_t foreground, pid_t ownProcess) {
    return CapturedScreenKeyboardTarget(foreground, ownProcess);
}

} // namespace msime::mac

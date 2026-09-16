#pragma once

#include <sys/types.h>

namespace msime::mac {

/// Keep an external foreground process as the screen-keyboard target.
/// The input method itself and invalid PIDs are never valid destinations.
inline pid_t CapturedScreenKeyboardTarget(pid_t candidate, pid_t ownProcess) {
    if (candidate <= 0 || candidate == ownProcess) return 0;
    return candidate;
}

} // namespace msime::mac

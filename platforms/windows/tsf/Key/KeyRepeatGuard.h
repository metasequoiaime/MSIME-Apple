#pragma once

#include <windows.h>

// Windows marks auto-repeat key-down messages with lParam bit 30.
inline bool IsAutoRepeat(LPARAM lParam)
{
    return (static_cast<ULONG_PTR>(lParam) & 0x40000000u) != 0;
}

inline bool ShouldSuppressBackspaceRepeat(bool armed, bool compositionActive, bool repeat)
{
    return armed && repeat && !compositionActive;
}

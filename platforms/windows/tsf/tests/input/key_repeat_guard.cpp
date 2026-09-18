#include "Key/KeyRepeatGuard.h"

int main()
{
    if (IsAutoRepeat(0) || !IsAutoRepeat(static_cast<LPARAM>(0x40000000u))) return 1;
    if (IsAutoRepeat(static_cast<LPARAM>(0x80000000u))) return 2;
    for (int mask = 0; mask < 8; ++mask) {
        const bool armed = (mask & 1) != 0;
        const bool active = (mask & 2) != 0;
        const bool repeat = (mask & 4) != 0;
        if (ShouldSuppressBackspaceRepeat(armed, active, repeat) != (armed && repeat && !active)) return 3;
    }
    return 0;
}

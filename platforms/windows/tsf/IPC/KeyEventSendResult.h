#pragma once

#include "../../common/KeyEventSendResult.h"

// Local transport outcome, not a serialized IPC field. The TSF DLL and the Server share one definition in common/; this header keeps the DLL's unqualified spelling.
using msime::windows::KeyEventSendResult;

// A necessary condition for local fallback, not permission to replay a key. The caller must still validate focus, composition and ownership.
constexpr bool IsDefinitelyNotSent(KeyEventSendResult result) noexcept
{
    return msime::windows::definitely_not_sent(result);
}

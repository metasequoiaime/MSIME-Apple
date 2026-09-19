#pragma once

#include <cstdint>

namespace msime::windows {
// This bit is attached only to the in-process event copy. It is never encoded
// on a pipe and lets the candidate surface distinguish a queue-backlogged hide
// from an ordinary commit/focus hide.
inline constexpr uint32_t internal_late_event = 1u << 31;
} // namespace msime::windows

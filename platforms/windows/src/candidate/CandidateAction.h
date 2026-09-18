#pragma once

#include <cstdint>

namespace msime::windows {
enum class CandidateAction : uint8_t {
  Select,
  Pin,
  Remove,
  FixPosition,
  ClearPosition,
};
} // namespace msime::windows

#pragma once

#include "../../vendor/MSIME-Engine/contracts/windows_ipc.h"

namespace msime::windows::PipeMetadata {
// Set by the TSF while its original candidate list is active. This metadata
// is distinct from keyboard modifiers: VK_RETURN has different semantics for
// an original candidate list and an incremental/raw composition.
inline constexpr std::uint32_t CandidateActive = 0x40000000u;

inline constexpr std::uint32_t key_modifiers(std::uint32_t value) {
  return value & ~(FanyImePipeFlags::UiLess | CandidateActive);
}
} // namespace msime::windows::PipeMetadata

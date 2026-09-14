#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace msime::windows {

enum class VoiceControlCommand : uint32_t { Start = 1, Stop = 2, Cancel = 3 };

struct VoiceControlMessage {
  VoiceControlCommand command;
  uint64_t client_id;
  uint64_t activation_epoch;
  uint64_t generation;
};

// Bounded UTF-16 text framing for the authenticated control pipe. The
// receiver still validates identity and epoch against PipeRegistry; this
// codec only validates the message shape and prevents oversized allocations.
inline constexpr size_t kVoiceControlMessageChars = 96;

std::optional<std::wstring> encode_voice_control(const VoiceControlMessage &message);
std::optional<VoiceControlMessage> decode_voice_control(std::wstring_view text);

} // namespace msime::windows

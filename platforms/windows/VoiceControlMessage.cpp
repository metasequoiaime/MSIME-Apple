#include "VoiceControlMessage.h"

#include <cerrno>
#include <cwchar>

namespace msime::windows {
namespace {
constexpr std::wstring_view prefix = L"MSIME_VOICE|";
bool number(std::wstring_view value, uint64_t &out) {
  if (value.empty()) return false;
  std::wstring copy(value);
  errno = 0;
  wchar_t *end = nullptr;
  const auto parsed = std::wcstoull(copy.c_str(), &end, 10);
  if (errno == ERANGE || end != copy.c_str() + copy.size()) return false;
  out = parsed;
  return true;
}
}

std::optional<std::wstring> encode_voice_control(const VoiceControlMessage &message) {
  if (message.client_id == 0 || message.activation_epoch == 0 || message.generation == 0)
    return std::nullopt;
  if (message.command < VoiceControlCommand::Start || message.command > VoiceControlCommand::Cancel)
    return std::nullopt;
  std::wstring text(prefix);
  text += std::to_wstring(static_cast<uint32_t>(message.command));
  text += L"|" + std::to_wstring(message.client_id) + L"|" +
          std::to_wstring(message.activation_epoch) + L"|" +
          std::to_wstring(message.generation);
  return text.size() <= kVoiceControlMessageChars ? std::optional(text) : std::nullopt;
}

std::optional<VoiceControlMessage> decode_voice_control(std::wstring_view text) {
  if (text.size() > kVoiceControlMessageChars || text.substr(0, prefix.size()) != prefix)
    return std::nullopt;
  text.remove_prefix(prefix.size());
  uint64_t values[4]{};
  size_t begin = 0;
  for (size_t index = 0; index < 4; ++index) {
    const size_t end = text.find(L'|', begin);
    const auto part = text.substr(begin, end == std::wstring_view::npos ? end : end - begin);
    if (!number(part, values[index]) || (index < 3 && end == std::wstring_view::npos) ||
        (index == 3 && end != std::wstring_view::npos)) return std::nullopt;
    begin = end == std::wstring_view::npos ? text.size() : end + 1;
  }
  if (values[0] < FanyImeVoiceControl::Start || values[0] > FanyImeVoiceControl::Cancel ||
      values[1] == 0 || values[2] == 0 || values[3] == 0)
    return std::nullopt;
  return VoiceControlMessage{static_cast<VoiceControlCommand>(values[0]), values[1], values[2], values[3]};
}
} // namespace msime::windows

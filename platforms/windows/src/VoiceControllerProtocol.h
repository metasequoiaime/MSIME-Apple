#pragma once
#include "voice_controller.h"
#include <cstring>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace msime::windows {
// Windows x86/x64/ARM64 are little endian, as required by the wire contract.
// Authentication, ordering and session ownership belong to the listener, not
// this framing adapter. No decoded payload may be logged.
struct VoiceControllerRequest {
  FanyImeVoiceController::Request header;
  std::string language;
};

inline bool controller_utf8(std::string_view text) {
  for (size_t i = 0; i < text.size();) {
    const auto first = static_cast<unsigned char>(text[i++]);
    if (!first) return false;
    if (first < 0x80) continue;
    size_t remaining = 0;
    uint32_t scalar = 0, minimum = 0;
    if (first >= 0xc2 && first <= 0xdf) {
      remaining = 1; scalar = first & 0x1f; minimum = 0x80;
    } else if (first >= 0xe0 && first <= 0xef) {
      remaining = 2; scalar = first & 0x0f; minimum = 0x800;
    } else if (first >= 0xf0 && first <= 0xf4) {
      remaining = 3; scalar = first & 0x07; minimum = 0x10000;
    } else return false;
    if (remaining > text.size() - i) return false;
    while (remaining--) {
      const auto next = static_cast<unsigned char>(text[i++]);
      if ((next & 0xc0) != 0x80) return false;
      scalar = (scalar << 6) | (next & 0x3f);
    }
    if (scalar < minimum || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff)) return false;
  }
  return true;
}

inline std::optional<VoiceControllerRequest>
decode_voice_controller_request(const std::vector<uint8_t> &bytes) {
  using namespace FanyImeVoiceController;
  if (bytes.size() < sizeof(Request) || bytes.size() > sizeof(Request) + MaxLanguageBytes)
    return std::nullopt;
  VoiceControllerRequest result{};
  std::memcpy(&result.header, bytes.data(), sizeof(Request));
  if (!valid_request(result.header, bytes.size())) return std::nullopt;
  result.language.assign(reinterpret_cast<const char *>(bytes.data() + sizeof(Request)), result.header.language_bytes);
  if (!controller_utf8(result.language)) return std::nullopt;
  for (const unsigned char ch : result.language)
    if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
          (ch >= '0' && ch <= '9') || ch == '-')) return std::nullopt;
  return result;
}

inline std::optional<std::vector<uint8_t>> encode_voice_controller_reply(
    FanyImeVoiceController::Reply reply, std::string_view text = {}) {
  using namespace FanyImeVoiceController;
  if (text.size() > MaxTextBytes || !controller_utf8(text)) return std::nullopt;
  reply.text_bytes = static_cast<uint32_t>(text.size());
  if (!valid_reply(reply, sizeof(Reply) + text.size())) return std::nullopt;
  std::vector<uint8_t> bytes(sizeof(Reply) + text.size());
  std::memcpy(bytes.data(), &reply, sizeof(Reply));
  if (!text.empty()) std::memcpy(bytes.data() + sizeof(Reply), text.data(), text.size());
  return bytes;
}
} // namespace msime::windows

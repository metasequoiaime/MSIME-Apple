#include "ReplyCodec.h"
#include <algorithm>
#include <charconv>

namespace msime::windows {
namespace {
EncodedReply failed(ReplyError error) { return {error, {}}; }
EncodedReply text_reply(uint64_t request, uint32_t type,
                        std::string_view text) {
  if (!request || request == FANY_IME_NO_REQUEST_ID)
    return failed(ReplyError::InvalidRequest);
  EncodedReply result;
  result.packet.request_id = request;
  result.packet.msg_type = type;
  size_t output = 0;
  for (size_t input = 0; input < text.size();) {
    const auto first = static_cast<uint8_t>(text[input++]);
    uint32_t scalar;
    uint32_t minimum;
    unsigned count;
    if (first < 0x80) {
      scalar = first;
      minimum = 0;
      count = 0;
    } else if (first >= 0xC2 && first <= 0xDF) {
      scalar = first & 0x1F;
      minimum = 0x80;
      count = 1;
    } else if (first >= 0xE0 && first <= 0xEF) {
      scalar = first & 0x0F;
      minimum = 0x800;
      count = 2;
    } else if (first >= 0xF0 && first <= 0xF4) {
      scalar = first & 0x07;
      minimum = 0x10000;
      count = 3;
    } else
      return failed(ReplyError::InvalidUtf8);
    if (text.size() - input < count)
      return failed(ReplyError::InvalidUtf8);
    for (unsigned index = 0; index < count; ++index) {
      auto next = static_cast<uint8_t>(text[input++]);
      if ((next & 0xC0) != 0x80)
        return failed(ReplyError::InvalidUtf8);
      scalar = (scalar << 6) | (next & 0x3F);
    }
    if (scalar < minimum || scalar > 0x10FFFF ||
        (scalar >= 0xD800 && scalar <= 0xDFFF))
      return failed(ReplyError::InvalidUtf8);
    if (scalar == 0)
      return failed(ReplyError::EmbeddedNul);
    const size_t units = scalar > 0xFFFF ? 2 : 1;
    if (output + units > FanyImePipeLimits::CandidateTextMaxLength)
      return failed(ReplyError::TooLong);
    if (units == 2) {
      scalar -= 0x10000;
      result.packet.candidate_string[output++] =
          static_cast<FanyImeWireChar>(0xD800 + (scalar >> 10));
      result.packet.candidate_string[output++] =
          static_cast<FanyImeWireChar>(0xDC00 + (scalar & 0x3FF));
    } else
      result.packet.candidate_string[output++] =
          static_cast<FanyImeWireChar>(scalar);
  }
  // Whole packet was zero-initialized: both terminator and unused tail stay
  // zero.
  return result;
}
bool contains_delimiter(std::string_view text) {
  return text.find('\t') != std::string_view::npos;
}
} // namespace
EncodedReply candidate_commit(uint64_t request, std::string_view text) {
  return text_reply(request, FanyImeReplyType::Normal, text);
}
EncodedReply exact_commit(uint64_t request, std::string_view text) {
  return text_reply(request, FanyImeReplyType::CommitExactText, text);
}
EncodedReply preedit_reply(uint64_t request, std::string_view text) {
  return text_reply(request, FanyImeReplyType::Preedit, text);
}
EncodedReply ignored_reply(uint64_t request) {
  return text_reply(request, FanyImeReplyType::NavigationIgnored, {});
}
namespace {
ReplyBytes packet_bytes(const FanyImeNamedpipeDataToTsf &packet) {
  ReplyBytes bytes{};
  const auto put = [&](size_t offset, uint64_t value, size_t width) {
    for (size_t index = 0; index < width; ++index)
      bytes[offset + index] = static_cast<uint8_t>(value >> (8 * index));
  };
  put(offsetof(FanyImeNamedpipeDataToTsf, msg_type), packet.msg_type, 4);
  put(offsetof(FanyImeNamedpipeDataToTsf, request_id), packet.request_id, 8);
  for (size_t index = 0; index < FanyImePipeLimits::CandidateTextCapacity;
       ++index)
    put(offsetof(FanyImeNamedpipeDataToTsf, candidate_string) + 2 * index,
        static_cast<uint16_t>(packet.candidate_string[index]), 2);
  return bytes;
}
} // namespace
std::optional<ReplyBytes> wire_bytes(const EncodedReply &reply) {
  if (!reply || !reply.packet.request_id ||
      reply.packet.request_id == FANY_IME_NO_REQUEST_ID)
    return std::nullopt;
  return packet_bytes(reply.packet);
}
std::optional<ReplyBytes>
protocol_reply_bytes(const FanyImeNamedpipeDataToTsf &packet) {
  if ((packet.msg_type != FanyImeReplyType::ProtocolReady &&
       packet.msg_type != FanyImeReplyType::ProtocolMismatch) ||
      !packet.request_id || packet.request_id == FANY_IME_NO_REQUEST_ID)
    return std::nullopt;
  return packet_bytes(packet);
}
std::optional<std::vector<uint8_t>> pipe_ready_bytes(uint32_t role) {
  if (role == FanyImePipeRole::ToTsf) {
    FanyImeNamedpipeDataToTsf packet{};
    packet.msg_type = FanyImeReplyType::PipeReady;
    const auto bytes = packet_bytes(packet);
    return std::vector<uint8_t>(bytes.begin(), bytes.end());
  }
  if (role != FanyImePipeRole::ToTsfWorkerThread)
    return std::nullopt;
  std::vector<uint8_t> bytes(sizeof(FanyImeNamedpipeDataToTsfWorkerThread), 0);
  for (size_t i = 0; i < sizeof(uint32_t); ++i)
    bytes[i] =
        static_cast<uint8_t>(FanyImeWorkerReplyType::PipeReady >> (8 * i));
  return bytes;
}
std::optional<std::vector<uint8_t>> focus_ready_bytes(uint64_t token) {
  if (!token)
    return std::nullopt;
  std::array<char, 20> decimal{};
  const auto converted =
      std::to_chars(decimal.data(), decimal.data() + decimal.size(), token);
  if (converted.ec != std::errc{})
    return std::nullopt;
  std::vector<uint8_t> bytes(sizeof(FanyImeNamedpipeDataToTsfWorkerThread), 0);
  for (size_t i = 0; i < sizeof(uint32_t); ++i)
    bytes[i] = static_cast<uint8_t>(FanyImeWorkerReplyType::FocusSessionReady >>
                                    (8 * i));
  const auto count = static_cast<size_t>(converted.ptr - decimal.data());
  for (size_t i = 0; i < count; ++i)
    bytes[offsetof(FanyImeNamedpipeDataToTsfWorkerThread, data) + 2 * i] =
        static_cast<uint8_t>(decimal[i]);
  return bytes;
}
EncodedReply partial_selection(uint64_t request, std::string_view raw,
                               std::string_view prefix,
                               std::string_view display) {
  if (raw.empty() || prefix.empty() || contains_delimiter(raw) ||
      contains_delimiter(prefix) || contains_delimiter(display) ||
      std::any_of(raw.begin(), raw.end(),
                  [](unsigned char c) { return c < 0x20 || c > 0x7E; }))
    return failed(ReplyError::InvalidFields);
  // Bound each field before allocating a composite string; a representable
  // UTF-8 scalar needs at most three bytes per UTF-16 code unit.
  constexpr size_t max_bytes = FanyImePipeLimits::CandidateTextMaxLength * 3;
  if (raw.size() > max_bytes || prefix.size() > max_bytes ||
      display.size() > max_bytes)
    return failed(ReplyError::TooLong);
  return text_reply(request, FanyImeReplyType::NeedToCreateWord,
                    std::string(raw) + '\t' + std::string(prefix) + '\t' +
                        std::string(display));
}
EncodedReply uiless_reply(uint64_t request, std::string_view display,
                          const std::vector<std::string> &page,
                          size_t highlighted) {
  if (contains_delimiter(display) || page.size() > 9 ||
      (page.empty() ? highlighted != 0 : highlighted >= page.size()))
    return failed(ReplyError::InvalidFields);
  constexpr size_t max_bytes = FanyImePipeLimits::CandidateTextMaxLength * 3;
  if (display.size() > max_bytes)
    return failed(ReplyError::TooLong);
  std::string payload(display);
  payload += '\t';
  for (size_t index = 0; index < page.size(); ++index) {
    const auto &candidate = page[index];
    // The existing delimiter protocol has no escaping. Refuse ambiguous
    // candidates rather than silently split, omit or change their text.
    if (candidate.empty() || contains_delimiter(candidate) ||
        candidate.find(',') != std::string::npos)
      return failed(ReplyError::InvalidFields);
    if (candidate.size() > max_bytes ||
        payload.size() + candidate.size() + 1 > max_bytes)
      return failed(ReplyError::TooLong);
    if (index)
      payload += ',';
    payload += candidate;
  }
  payload += '\t';
  payload += std::to_string(highlighted);
  return text_reply(request, FanyImeReplyType::UiLessComposition, payload);
}
} // namespace msime::windows

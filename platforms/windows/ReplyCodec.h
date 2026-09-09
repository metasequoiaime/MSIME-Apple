#pragma once
#include "windows_ipc.h"
#include <array>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace msime::windows {
enum class ReplyError {
  None,
  InvalidRequest,
  InvalidUtf8,
  EmbeddedNul,
  TooLong,
  InvalidFields
};
struct EncodedReply {
  ReplyError error = ReplyError::None;
  FanyImeNamedpipeDataToTsf packet{};
  explicit operator bool() const { return error == ReplyError::None; }
};
// These are wire encoders, not decisions about which reply a TSF key path
// reads. The sender must revalidate client/activation ownership before writing
// a frame.
EncodedReply candidate_commit(uint64_t request, std::string_view complete_text);
EncodedReply exact_commit(uint64_t request, std::string_view complete_text);
EncodedReply preedit_reply(uint64_t request, std::string_view display_text);
EncodedReply ignored_reply(uint64_t request);
// Serialize members explicitly as little-endian bytes; never send struct
// padding.
using ReplyBytes = std::array<uint8_t, sizeof(FanyImeNamedpipeDataToTsf)>;
std::optional<ReplyBytes> wire_bytes(const EncodedReply &reply);
// Existing DLL expects remaining raw input, the ENTIRE selected prefix and the
// display preedit. Do not pass only the latest incremental Engine commit here.
EncodedReply partial_selection(uint64_t request, std::string_view remaining_raw,
                               std::string_view selected_prefix,
                               std::string_view display_preedit);
EncodedReply uiless_reply(uint64_t request, std::string_view display_preedit,
                          const std::vector<std::string> &page,
                          size_t highlighted);
} // namespace msime::windows

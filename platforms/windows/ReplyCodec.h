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
enum class NavigationReply {
  Ignored,
  PreviousCandidate,
  NextCandidate,
  PreviousPage,
  NextPage
};
// Navigation replies carry intent, even when already at a page/list boundary.
// They are never candidate text and do not commit composition.
EncodedReply navigation_reply(uint64_t request, NavigationReply navigation);
// Serialize members explicitly as little-endian bytes; never send struct
// padding.
using ReplyBytes = std::array<uint8_t, sizeof(FanyImeNamedpipeDataToTsf)>;
std::optional<ReplyBytes> wire_bytes(const EncodedReply &reply);
// Registration-only frames. These must never enter the candidate reply queue.
std::optional<std::vector<uint8_t>> pipe_ready_bytes(uint32_t role);
// Worker focus fence echoes the TSF activation request token, NOT the Server
// epoch. Caller must check current client/activation/transport ownership and
// order this before subsequent worker output. Encoding is not authorization.
std::optional<std::vector<uint8_t>> focus_ready_bytes(uint64_t focus_token);
std::optional<ReplyBytes>
protocol_reply_bytes(const FanyImeNamedpipeDataToTsf &packet);
// Existing DLL expects remaining raw input, the ENTIRE selected prefix and the
// display preedit. Do not pass only the latest incremental Engine commit here.
EncodedReply partial_selection(uint64_t request, std::string_view remaining_raw,
                               std::string_view selected_prefix,
                               std::string_view display_preedit);
EncodedReply uiless_reply(uint64_t request, std::string_view display_preedit,
                          const std::vector<std::string> &page,
                          size_t highlighted);
} // namespace msime::windows

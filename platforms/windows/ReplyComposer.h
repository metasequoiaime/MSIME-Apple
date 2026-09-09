#pragma once
#include "ReplyCodec.h"
#include "ServerSession.h"
#include <optional>

namespace msime::windows {
// Supplied by the TSF-compatible dispatch path, not inferred from a VK alone:
// e.g. a digit in Unicode mode is composition, not candidate selection.
enum class ReplyPath {
  Composition,
  Selection,
  Punctuation,
  LocalCommit,
  LocalCancel,
  NoReply,
  PreviousCandidate,
  NextCandidate,
  PreviousPage,
  NextPage,
  IgnoredNavigation
};
struct PendingReply {
  KeyResult source;
  std::optional<EncodedReply> encoded;
  std::string next_prefix;
};
// One instance per authenticated client activation, on the Server input queue.
// prefix is transport presentation state: text already selected by Engine but
// not yet committed by the legacy DLL. It never selects or edits Engine input.
class ReplyComposer final {
public:
  ReplyComposer(uint64_t client, uint64_t epoch);
  const PendingReply &
  stage(const KeyResult &result, ReplyPath path, bool uiless = false,
        std::optional<std::string> local_text = std::nullopt);
  // Normal input entry: enforce the pending-reply gate BEFORE advancing Engine.
  const PendingReply &
  dispatch(ServerSession &session, const FanyImeNamedpipeData &packet,
           uint64_t epoch, ReplyPath path, bool uiless = false,
           std::optional<std::string> local_text = std::nullopt);
  const PendingReply &pending() const;
  // Disabled navigation returns an ignored reply (UILess: unchanged page).
  // Null means this is not a navigation path; Engine is unchanged.
  // Caller may then run its ordinary TSF path. UiLess is read from the packet.
  std::optional<PendingReply> navigate(ServerSession &session,
                                       const FanyImeNamedpipeData &packet,
                                       uint64_t epoch,
                                       const NavigationBindings &bindings);
  bool has_pending() const { return pending_.has_value(); }
  // Call only after a complete frame write or successful local-only handling.
  // A failed/uncertain write leaves pending unchanged; never rerun Engine
  // input.
  void confirm_delivery(uint64_t client, uint64_t epoch, uint64_t request);
  // Explicit focus/transport cancellation; never an implicit error fallback.
  void cancel();
  const std::string &selected_prefix() const { return prefix_; }

private:
  uint64_t client_;
  uint64_t epoch_;
  uint64_t session_ = 0;
  std::string prefix_;
  std::optional<PendingReply> pending_;
};
} // namespace msime::windows

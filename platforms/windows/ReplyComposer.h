#pragma once
#include "ReplyCodec.h"
#include "EditPolicy.h"
#include "ServerSession.h"
#include <optional>

namespace msime::windows {
// Supplied by the TSF-compatible dispatch path, not inferred from a VK alone:
// e.g. a digit in Unicode mode is composition, not candidate selection.
enum class ReplyPath {
  Composition,
  Selection,
  Punctuation,
  CandidatePunctuationFallback,
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
  std::optional<UiSelectionFrames> ui_selection = std::nullopt;
  // A copied, bounded query for the optional asynchronous cloud provider.
  // It is submitted only after this reply has been delivered and confirmed.
  std::optional<std::string> online_query = std::nullopt;
  // A copied, bounded candidate-translation query, submitted after delivery.
  std::optional<std::string> translation_query = std::nullopt;
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
  // LocalCommit also requires an Enter/raw-commit key and caller-observed text
  // equal to selected_prefix + Engine editing_text BEFORE clearing composition.
  const PendingReply &
  dispatch(ServerSession &session, const FanyImeNamedpipeData &packet,
           uint64_t epoch, ReplyPath path, bool uiless = false,
           std::optional<std::string> local_text = std::nullopt);
  const PendingReply &pending() const;
  // Resolve special-profile and other native-only shortcuts first.
  std::optional<PendingReply> configured_key(
      ServerSession &session, const FanyImeNamedpipeData &packet,
      uint64_t epoch, TsfPreeditStyle style, const NavigationBindings &bindings,
      std::optional<std::string> local_text = std::nullopt,
      WordCharacterBinding word_binding = WordCharacterBinding::Disabled);
  // Native configuration-specific priority routes must run first. Null leaves
  // Engine untouched and means this key needs another native route.
  std::optional<PendingReply> basic_key(ServerSession &session,
      const FanyImeNamedpipeData &packet, uint64_t epoch, TsfPreeditStyle style,
      std::optional<std::string> local_text = std::nullopt);
  // Null: not an editing key; no Engine action. Non-null may have no frame
  // because TSF completed this edit locally; still confirm it through the pump.
  std::optional<PendingReply> edit(ServerSession &session,
      const FanyImeNamedpipeData &packet, uint64_t epoch, TsfPreeditStyle style);
  // Disabled navigation returns an ignored reply (UILess: unchanged page).
  // Null means this is not a navigation path; Engine is unchanged.
  // Caller may then run its ordinary TSF path. UiLess is read from the packet.
  std::optional<PendingReply> navigate(ServerSession &session,
                                       const FanyImeNamedpipeData &packet,
                                       uint64_t epoch,
                                       const NavigationBindings &bindings);
  bool has_pending() const { return pending_.has_value(); }
  // Stale/busy clicks are rejected without advancing Engine. UI receipts use
  // the resulting view generation, not the id-zero wire request identifier.
  std::optional<PendingReply> select_candidate(ServerSession &session,
      uint64_t expected_session, uint64_t generation, size_t index);
  void confirm_ui_delivery(uint64_t client, uint64_t epoch, uint64_t generation);
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

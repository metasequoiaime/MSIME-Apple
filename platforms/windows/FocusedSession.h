#pragma once
#include "FocusGate.h"
#include "ReplyComposer.h"
#include <functional>

namespace msime::windows {
// One registered client's queue-owned adapter. No pipe I/O runs here; the
// controller prepares on the input queue, writes the focus fence on an I/O
// worker, then enqueues keys. It must cancel the previous client's session too.
class FocusedSession final {
public:
  FocusedSession(FocusGate &gate, uint64_t client, const std::string &options)
      : gate_(gate), client_(client), session_(client, options) {}
  bool prepare(const FocusLease &lease);
  // No operation may invalidate a key reply awaiting transport confirmation.
  std::optional<nlohmann::json> dedicated_english(const FocusLease &lease, bool exit);
  std::optional<PendingReply>
  key(const FocusLease &lease, const FanyImeNamedpipeData &packet,
      ReplyPath path, bool uiless = false,
      std::optional<std::string> local_text = std::nullopt);
  // Only queue this after successful I/O or verified local-only completion.
  // A false return means the receipt is obsolete; never replay the key.
  bool confirm(const FocusLease &lease, uint64_t request);
  std::optional<PendingReply> select_candidate(const FocusLease &lease,
      uint64_t session, uint64_t generation, size_t index);
  std::optional<nlohmann::json>
  candidate_action(const FocusLease &lease, uint64_t session,
                   uint64_t generation, size_t index, CandidateAction action,
                   uint8_t position = 0);
  std::optional<nlohmann::json>
  page_candidate(const FocusLease &lease, uint64_t session,
                 uint64_t generation, bool previous, unsigned steps);
  bool confirm_ui(const FocusLease &lease, uint64_t generation);
  std::optional<PendingReply> configured_key(
      const FocusLease &lease, const FanyImeNamedpipeData &packet,
      TsfPreeditStyle style, const NavigationBindings &bindings,
      std::optional<std::string> local_text = std::nullopt,
      WordCharacterBinding word_binding = WordCharacterBinding::Disabled);
  std::optional<PendingReply> basic_key(const FocusLease &lease,
      const FanyImeNamedpipeData &packet, TsfPreeditStyle style,
      std::optional<std::string> local_text = std::nullopt);
  std::optional<PendingReply> toggle_character_set(
      const FocusLease &lease, const FanyImeNamedpipeData &packet,
      bool enabled, const std::function<bool(bool)> &persist);
  std::optional<PendingReply> edit(const FocusLease &lease,
      const FanyImeNamedpipeData &packet, TsfPreeditStyle style);
  std::optional<PendingReply> navigate(const FocusLease &lease,
                                       const FanyImeNamedpipeData &packet,
                                       const NavigationBindings &bindings);
  std::optional<nlohmann::json>
  apply_cloud_response(const FocusLease &lease, const std::string &query,
                       const std::string &body);
  std::optional<nlohmann::json> apply_ai_candidates(const FocusLease &lease,
                                                    const std::string &query,
                                                    const std::string &candidates);
  std::optional<std::string> translation_query(const FocusLease &lease);
  std::optional<nlohmann::json>
  apply_translations(const FocusLease &lease, uint64_t generation,
                     const std::string &translations);
  // Recover the staged result without rerunning Engine. This does NOT permit
  // blindly resending a frame whose previous delivery is uncertain.
  std::optional<PendingReply> pending(const FocusLease &lease);
  // Retry the latest snapshot after a pending reply is confirmed. Do not let
  // configuration mutate Engine/view state while an earlier result is unsent.
  std::optional<nlohmann::json> update_preferences(const FocusLease &lease,
                                                   const std::string &snapshot);
  bool cancel(const FocusLease &lease);
  // Deactivate at the DLL's request, which names a focus token rather than a
  // lease it has no way to construct. True also when this client is already
  // not focused on that token: the state the caller asked for holds either
  // way, and it is the state - not the act - that is being reported.
  bool cancel_focus_token(uint64_t token);
  // Explicit host composition termination, preserving the active focus lease.
  bool cancel_composition(const FocusLease &lease);
  // Queue-owned maintenance operation; it is available without a focus lease.
  bool reset_cache();
  bool set_input_enabled(const FocusLease &lease, bool enabled);
  bool set_chinese_punctuation(const FocusLease &lease, bool enabled);
  // Retain at most one latest snapshot while a reply is pending. True means
  // accepted for delivery, not necessarily applied to an active composition.
  bool queue_preferences(const FocusLease &lease, const std::string &snapshot);
  // Queue-owned settings broadcast, not an external focus authorization API.
  bool queue_current_preferences(const std::string &snapshot);
  nlohmann::json view() const { return session_.view(); }

private:
  void check_thread() const;
  bool prepared(const FocusLease &lease) const;
  void attach_online_query(const FocusLease &lease,
                           std::optional<PendingReply> &reply);
  FocusGate &gate_;
  uint64_t client_;
  const std::thread::id thread_ = std::this_thread::get_id();
  ServerSession session_;
  std::optional<FocusLease> lease_;
  std::optional<ReplyComposer> composer_;
  std::optional<nlohmann::json> preferences_retry_;
};
} // namespace msime::windows

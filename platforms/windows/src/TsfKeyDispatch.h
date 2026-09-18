#pragma once

#include "KeyEventSendResult.h"

namespace msime::windows {

enum class TsfKeyDispatchResult { Complete, Retry, AwaitingCompletion };

struct TsfKeyDispatchDecision {
  TsfKeyDispatchResult result = TsfKeyDispatchResult::Complete;
  bool eaten = true;
  bool deferred_replay = false;
};

// Mirrors the native TSF rule: an uncertain write is never replayed inline.
// If a replay fence can be established, the host queues the original key and
// completes this callback; otherwise the key is returned for the host's retry
// path. A failed queue must release the key instead of silently dropping it.
constexpr TsfKeyDispatchDecision decide_tsf_key_dispatch(
    KeyEventSendResult send, bool can_defer, bool queued) noexcept {
  if (send == KeyEventSendResult::Sent)
    return {TsfKeyDispatchResult::Complete, true, false};
  if (!can_defer)
    return {TsfKeyDispatchResult::Retry, true, false};
  if (queued)
    return {TsfKeyDispatchResult::AwaitingCompletion, true, true};
  return {TsfKeyDispatchResult::Complete, false, false};
}

} // namespace msime::windows

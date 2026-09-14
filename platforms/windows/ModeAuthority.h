#pragma once
#include <cstdint>

namespace msime::windows {
// Cross-application CN/EN authority.
//
// With input.ime_mode_scope set to "global" the user expects one Chinese or
// English state to follow them between applications. Each TSF client keeps its
// own mode, so the Server has to be the authority: when a different client
// takes focus it reports whatever mode it happens to hold, and the Server
// pushes its own back. Without this the choice was per-application only, which
// is the behaviour the "按应用记忆" option already describes.
struct ModeAuthorityState {
  bool chinese = true;
  bool seeded = false;
  // The focused client's session id, so a change of client is distinguishable
  // from the same client changing its own mode.
  uint64_t session = 0;
};
struct ModeAuthorityDecision {
  // Send a mode switch to the focused client.
  bool push = false;
  bool push_chinese = true;
  // The authority after this observation.
  ModeAuthorityState next;
};
// Decide what to do with one observation of the focused client's mode.
//
// `global` is the configured scope, `focused` whether a client is focused at
// all, and `reported` the mode that client says it is in.
inline ModeAuthorityDecision
mode_authority_step(const ModeAuthorityState &state, bool global, bool focused,
                    uint64_t session, bool reported) {
  ModeAuthorityDecision decision;
  decision.next = state;
  if (!focused)
    return decision; // Nothing focused: keep the authority, push nothing.
  if (!global) {
    // Per-application memory. Track the session so switching the option on
    // later does not immediately treat the current client as a new one, but
    // never push: each application keeps its own mode, as the option says.
    decision.next.session = session;
    decision.next.chinese = reported;
    decision.next.seeded = true;
    return decision;
  }
  if (!state.seeded) {
    // First observation seeds the authority rather than fighting the client.
    decision.next.chinese = reported;
    decision.next.seeded = true;
    decision.next.session = session;
    return decision;
  }
  if (session != state.session) {
    // A different client took focus. It reports its own mode; the authority
    // wins, and only differences are pushed so an already-correct client is
    // left alone.
    decision.next.session = session;
    if (reported != state.chinese) {
      decision.push = true;
      decision.push_chinese = state.chinese;
    }
    return decision;
  }
  // Same client, new mode: the user changed it deliberately, so it becomes the
  // authority and travels to the next application.
  decision.next.chinese = reported;
  return decision;
}
} // namespace msime::windows

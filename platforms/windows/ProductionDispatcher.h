#pragma once

#include "KeyEvent.h"
#include "SessionPump.h"

namespace msime::windows {
// Production TSF clients receive their input policy from the validated
// preference snapshot owned by InputState.  Do not capture launch-time preview
// values here: the preference monitor can publish a newer snapshot while a
// client remains focused, and the next key must use that snapshot atomically.
inline SessionPump::KeyHandler production_key_handler() {
  return [](InputState &state, const FocusLease &focus,
            const FanyImeNamedpipeData &packet) {
    return state.configured_key(
        focus, packet, state.tsf_preedit_style(), state.navigation_bindings(),
        local_commit_observation(packet), state.word_character_binding());
  };
}
} // namespace msime::windows

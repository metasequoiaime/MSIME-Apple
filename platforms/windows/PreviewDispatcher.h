#pragma once
#include "KeyEvent.h"
#include "PreviewConfig.h"
#include "SessionPump.h"

namespace msime::windows {
// Explicit launch bindings override the latest shared input-thread publication.
// The launch preedit style is required and always explicit: the preview host
// declares how it renders composition, so a shared preference published later
// must not silently change which frames that host receives.
inline SessionPump::KeyHandler
preview_key_handler(const PreviewConfig &config) {
  return
      [style = config.style, navigation = config.navigation,
       explicit_keys = config.explicit_key_bindings,
       word = config.word_character](InputState &state, const FocusLease &focus,
                                     const FanyImeNamedpipeData &packet) {
        return state.configured_key(focus, packet, style,
                                    explicit_keys ? navigation
                                                  : state.navigation_bindings(),
                                    local_commit_observation(packet),
                                    explicit_keys ? word : state.word_character_binding());
      };
}
} // namespace msime::windows

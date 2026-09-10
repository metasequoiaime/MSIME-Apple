#pragma once
#include "PreviewConfig.h"
#include "SessionPump.h"

namespace msime::windows {
// Explicit launch bindings override the latest shared input-thread publication.
inline SessionPump::KeyHandler
preview_key_handler(const PreviewConfig &config) {
  return
      [navigation = config.navigation,
       explicit_keys = config.explicit_key_bindings,
       word = config.word_character](InputState &state, const FocusLease &focus,
                                     const FanyImeNamedpipeData &packet) {
        return state.configured_key(focus, packet, state.tsf_preedit_style(),
                                    explicit_keys ? navigation
                                                  : state.navigation_bindings(),
                                    std::nullopt, explicit_keys ? word : state.word_character_binding());
      };
}
} // namespace msime::windows

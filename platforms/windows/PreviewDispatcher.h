#pragma once
#include "PreviewConfig.h"
#include "SessionPump.h"

namespace msime::windows {
// Capture a startup snapshot, not the configuration file or mutable UI state.
// Native key bindings are independent of deferred Engine preference changes.
inline SessionPump::KeyHandler
preview_key_handler(const PreviewConfig &config) {
  return
      [style = config.style, navigation = config.navigation,
       word = config.word_character](InputState &state, const FocusLease &focus,
                                     const FanyImeNamedpipeData &packet) {
        return state.configured_key(focus, packet, style, navigation,
                                    std::nullopt, word);
      };
}
} // namespace msime::windows

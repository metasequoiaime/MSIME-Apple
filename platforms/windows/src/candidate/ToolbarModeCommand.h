#pragma once
#include "ReplyCodec.h"
#include "ToolbarIcons.h"

namespace msime::windows {
// The worker protocol sets modes explicitly; it has no toggle opcode.
// Unknown is not false: wait for the focused TIP's reported state.
inline std::optional<WorkerMode> toolbar_mode_command(
    int button, std::optional<bool> chinese, std::optional<bool> fullwidth,
    std::optional<bool> chinese_punctuation) {
  switch (button) {
  case kToolbarLanguage:
    if (chinese) return *chinese ? WorkerMode::English : WorkerMode::Chinese;
    break;
  case kToolbarFullwidth:
    if (fullwidth) return *fullwidth ? WorkerMode::Halfwidth : WorkerMode::Fullwidth;
    break;
  case kToolbarPunctuation:
    if (chinese_punctuation)
      return *chinese_punctuation ? WorkerMode::AsciiPunctuation
                                 : WorkerMode::ChinesePunctuation;
    break;
  default:
    break;
  }
  return std::nullopt;
}
} // namespace msime::windows

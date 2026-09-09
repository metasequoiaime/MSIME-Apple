#pragma once
#include "KeyEvent.h"
#include <string_view>

namespace msime::windows {
enum class TsfPreeditStyle { Local, Pinyin };
enum class EditKind { None, Character, Erase, Caret };
// Only composition editing. Native priority paths (shortcuts,
// word-to-character, punctuation and navigation) remain separate; never infer
// Engine mode from text.
inline EditKind edit_kind(const FanyImeNamedpipeData &packet,
                          std::string_view mode, bool composing) {
  if (packet.event_type != FanyImePipeEventType::KeyEvent || mode == "unknown")
    return EditKind::None;
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  if (modifiers & ~1u)
    return EditKind::None;
  const auto key = normalize_digit_key(packet.keycode);
  const auto text = static_cast<uint32_t>(packet.wch);
  if (composing && modifiers == 0) {
    if (key == 0x08 || key == 0x2E)
      return EditKind::Erase;
    if (key == 0x25 || key == 0x27)
      return EditKind::Caret;
  }
  if (translate_key(packet).kind != KeyKind::Character)
    return EditKind::None;
  if (composing && modifiers == 0 && text == '\'' && mode == "none")
    return EditKind::Character;
  if (key >= 'A' && key <= 'Z' &&
      ((text >= 'a' && text <= 'z') || (text >= 'A' && text <= 'Z')))
    return EditKind::Character;
  if (mode == "unicode") {
    if (modifiers == 1 && key >= '1' && key <= '9')
      return EditKind::None;
    if (modifiers == 0 && key >= '0' && key <= '9')
      return EditKind::Character;
    if (text == '+')
      return EditKind::Character;
  }
  return EditKind::None;
}
} // namespace msime::windows

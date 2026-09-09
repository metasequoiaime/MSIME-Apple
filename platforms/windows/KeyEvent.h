#pragma once
#include "msime_client.h"
#include "windows_ipc.h"

namespace msime::windows {
enum class KeyKind { Ignore, LocalReset, CancelAndForward, Character, Command };
struct KeyAction {
  KeyKind kind = KeyKind::Ignore;
  uint32_t value = 0;
  bool shift = false;
};

// Match the legacy Server boundary: TSF classifies both digit rows as
// candidate keys. Preserve the original packet for request/transport checks.
inline constexpr uint32_t normalize_digit_key(uint32_t key) {
  return key >= 0x60 && key <= 0x69 ? '0' + key - 0x60 : key;
}

// Win32 VK values are stable wire values, not characters. Text comes from wch,
// already translated by TSF using the active keyboard layout. No ToUnicode call
// belongs on the Server thread. Modifiers are the TSF protocol bitset, not
// MK_*.
inline KeyAction translate_key(const FanyImeNamedpipeData &packet) {
  if (packet.event_type != FanyImePipeEventType::KeyEvent)
    return {};
  const auto key = packet.keycode;
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  // Existing TSF consumes these locally and tells Server to cancel without a
  // reverse-pipe key reply. This differs from raw OS modifier key-down
  // handling.
  if (key == 0x10 || key == 0xA0 || key == 0xA1 || key == 0x1B)
    return {KeyKind::LocalReset, MSIME_CANCEL};
  if (key == 0x11 || key == 0x12 || (key >= 0xA2 && key <= 0xA5) ||
      key == 0x5B || key == 0x5C)
    return {};
  if (modifiers & ~1u)
    return {KeyKind::CancelAndForward, MSIME_CANCEL};
  switch (key) {
  case 0x08:
    return {KeyKind::Command, MSIME_BACKSPACE};
  case 0x0D:
    return {KeyKind::Command, MSIME_COMMIT_RAW};
  case 0x20:
    return {KeyKind::Command, MSIME_COMMIT_CANDIDATE};
  case 0x21:
    return {KeyKind::Command, MSIME_PREVIOUS_PAGE};
  case 0x22:
    return {KeyKind::Command, MSIME_NEXT_PAGE};
  case 0x23:
    return {KeyKind::Command, MSIME_MOVE_END};
  case 0x24:
    return {KeyKind::Command, MSIME_MOVE_HOME};
  case 0x25:
    return {KeyKind::Command, MSIME_MOVE_LEFT};
  case 0x26:
    return {KeyKind::Command, MSIME_PREVIOUS_CANDIDATE};
  case 0x27:
    return {KeyKind::Command, MSIME_MOVE_RIGHT};
  case 0x28:
    return {KeyKind::Command, MSIME_NEXT_CANDIDATE};
  case 0x2E:
    return {KeyKind::Command, MSIME_DELETE_FORWARD};
  }
  if (key >= 0x60 && key <= 0x69)
    return {KeyKind::Character, normalize_digit_key(key), false};
  const auto text = static_cast<uint32_t>(packet.wch);
  if (text >= 0x21 && text <= 0x7E)
    return {KeyKind::Character, text, (modifiers & 1u) != 0};
  return {KeyKind::CancelAndForward, MSIME_CANCEL};
}
} // namespace msime::windows

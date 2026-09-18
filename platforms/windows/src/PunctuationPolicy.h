#pragma once
#include "KeyEvent.h"
#include "NavigationPolicy.h"
#include <string_view>

namespace msime::windows {
// Native routing only, not translation. Resolve input separators, Unicode
// selection and word-to-character priority before calling this predicate.
inline bool candidate_punctuation(const FanyImeNamedpipeData &packet,
                                  const NavigationBindings &bindings) {
  if (translate_key(packet).kind != KeyKind::Character)
    return false;
  switch (packet.keycode) {
  case 0xBD:
  case 0xBB:
  case 0x6D:
  case 0x6B:
    return false;
  case 0xBC:
  case 0xBE:
    if (bindings.comma_period)
      return false;
    break;
  case 0xDB:
  case 0xDD:
    if (bindings.brackets)
      return false;
    break;
  }
  constexpr std::string_view characters = "`!@#$%^&*()[]\\;:'\",<>.?";
  return packet.wch <= 127 && characters.find(static_cast<char>(packet.wch)) !=
                                  std::string_view::npos;
}
} // namespace msime::windows

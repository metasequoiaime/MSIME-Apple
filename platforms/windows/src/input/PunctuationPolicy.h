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

// The ASCII mark that follows the highlighted candidate literally, or 0 when the key's punctuation is translated as usual. The numpad arithmetic keys and '/' stay literal and the numpad decimal is always '.', so an expression or a path typed right after a candidate does not become Chinese punctuation (reference 1d2431ad). The numpad '+' and '-' are arithmetic, not the paging keys candidate_punctuation excludes. Only meaningful while composing: the caller routes these keys here only then.
inline char literal_candidate_punctuation(const FanyImeNamedpipeData &packet) {
  if (translate_key(packet).kind != KeyKind::Character)
    return 0;
  switch (packet.keycode) {
  case 0x6B:
    return '+';
  case 0x6D:
    return '-';
  case 0x6E:
    return '.';
  case 0x6F:
    return '/';
  }
  return packet.wch == '/' ? '/' : 0;
}
} // namespace msime::windows

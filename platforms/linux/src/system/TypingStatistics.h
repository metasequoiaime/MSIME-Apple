#pragma once

#include <string_view>

namespace msime::linux_host {

enum class TypingSource {
  Quanpin,
  NineKey,
  Shuangpin,
  Ziranma,
  Microsoft,
  Shoudao,
  Wubi,
  Japanese,
  Handwriting,
  English,
  Local,
  Ai,
  Reply,
  Voice,
  Unknown,
};

constexpr std::string_view typing_source_id(TypingSource source) {
  switch (source) {
  case TypingSource::Quanpin:
    return "quanpin";
  case TypingSource::NineKey:
    return "nineKey";
  case TypingSource::Shuangpin:
    return "shuangpin";
  case TypingSource::Ziranma:
    return "ziranma";
  case TypingSource::Microsoft:
    return "microsoft";
  case TypingSource::Shoudao:
    return "shoudao";
  case TypingSource::Wubi:
    return "wubi";
  case TypingSource::Japanese:
    return "japanese";
  case TypingSource::Handwriting:
    return "handwriting";
  case TypingSource::English:
    return "english";
  case TypingSource::Local:
    return "local";
  case TypingSource::Ai:
    return "ai";
  case TypingSource::Reply:
    return "reply";
  case TypingSource::Voice:
    return "voice";
  case TypingSource::Unknown:
    return "unknown";
  }
  return "unknown";
}

// The shared Engine exposes numeric schemes in its View: 0 quanpin, 1
// shuangpin, 2 wubi, and 3 Japanese. Local modes take precedence over the
// keyboard scheme, matching the Android and Apple hosts.
constexpr TypingSource
resolve_typing_source(int scheme, bool nine_key, bool dedicated_english,
                      std::string_view local_mode,
                      std::string_view shuangpin_profile) {
  if (local_mode == "temporary_japanese")
    return TypingSource::Japanese;
  if (!local_mode.empty() && local_mode != "none")
    return TypingSource::Local;
  if (dedicated_english)
    return TypingSource::English;
  switch (scheme) {
  case 0:
    return nine_key ? TypingSource::NineKey : TypingSource::Quanpin;
  case 1:
    if (shuangpin_profile == "ziranma")
      return TypingSource::Ziranma;
    if (shuangpin_profile == "microsoft")
      return TypingSource::Microsoft;
    if (shuangpin_profile == "shoudao")
      return TypingSource::Shoudao;
    return TypingSource::Shuangpin;
  case 2:
    return TypingSource::Wubi;
  case 3:
    return TypingSource::Japanese;
  default:
    return TypingSource::Unknown;
  }
}

// Modifiers that turn a key press into a shortcut rather than typed text. Shift and the level-3/level-5 shifts are deliberately absent: they select which character a key produces, so a character typed with them is still text.
struct PassthroughModifiers {
  bool control = false;
  bool alt = false;
  bool super = false;
  bool hyper = false;
  bool meta = false;
};

// Whether a key the IME handed back to the application still counts as a typed character. Mirrors the Windows ShouldCountPassthroughChar rule: no shortcut modifier held, and a printable scalar value - no C0 control, no DEL, no surrogate, nothing past U+10FFFF. The caller has already ruled out releases, keys the IME consumed, and blocked or private contexts.
constexpr bool should_count_passthrough_character(char32_t character,
                                                  PassthroughModifiers held) {
  if (held.control || held.alt || held.super || held.hyper || held.meta)
    return false;
  if (character < 0x20 || character == 0x7f || character > 0x10ffff)
    return false;
  return character < 0xd800 || character > 0xdfff;
}

} // namespace msime::linux_host

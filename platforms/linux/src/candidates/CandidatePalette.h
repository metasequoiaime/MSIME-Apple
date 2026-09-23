#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

namespace msime::linux_host {

// IBus candidate attributes carry RGB values, not alpha or geometry. Keep the
// RGB tokens aligned with the native presenters and let the Linux renderer
// apply only the properties the host protocol can represent.
struct CandidateBuiltinPalette {
  std::uint32_t surface;
  std::uint32_t text;
  std::uint32_t number;
  std::uint32_t accent;
  std::optional<std::uint32_t> selected;
  std::optional<std::uint32_t> selected_text;
  std::optional<std::uint32_t> selected_number;
  // The card's outline, from the same Windows skin tokens (platforms/windows/src/candidate/CandidatePalette.h): RGB, the alpha the skin draws it at, and a width in whole pixels. The Windows card strokes fluent with a 1.5 DIP antialiased Direct2D outline (wechat and graphite at 1), while Fcitx5 classic UI's BorderWidth only takes whole pixels, so every outlined skin is 1 here as the closest width that keeps the layout unchanged; willow_green draws none.
  std::uint32_t border = 0;
  std::uint8_t border_alpha = 0;
  int border_width = 0;
};

inline bool candidate_builtin_skin(std::string_view skin) {
  return skin == "fluent" || skin == "wechat" || skin == "graphite" ||
         skin == "willow_green";
}

inline CandidateBuiltinPalette candidate_builtin_palette(std::string_view skin,
                                                         bool dark) {
  // Fluent is the fallback for unknown ids. IBus cannot carry fluent's alpha
  // on the selected row, so selected stores the same RGB token without alpha.
  CandidateBuiltinPalette palette =
      dark ? CandidateBuiltinPalette{0x202020, 0xE9E8E8, 0xE9E8E8, 0x6B69D6,
                                     0x3E3E3E, std::nullopt, std::nullopt}
           : CandidateBuiltinPalette{0xFFFFFF, 0x1A1A1A, 0x1A1A1A, 0x6B69D6,
                                     0xE8E8E8, std::nullopt, std::nullopt};
  // Fluent outlines the card with a translucent line: black at 0.12 on light, #9B9B9B at 0.18 on dark.
  palette.border = dark ? 0x9B9B9B : 0x000000;
  palette.border_alpha = dark ? 0x2E : 0x1F;
  palette.border_width = 1;
  if (skin == "wechat") {
    palette.surface = dark ? 0x151515 : 0xF7F7F7;
    palette.text = dark ? 0xB7B7B7 : 0x333333;
    palette.number = dark ? 0x858585 : 0x757575;
    palette.accent = 0x07C160;
    palette.selected = palette.accent;
    palette.selected_text = palette.selected_number = 0xFFFFFF;
    palette.border = dark ? 0x292929 : 0xDEDEDE;
    palette.border_alpha = 0xFF;
  } else if (skin == "graphite") {
    palette.surface = dark ? 0x1C1F23 : 0xFBFBFC;
    palette.text = dark ? 0xAEB6C2 : 0x586476;
    palette.number = dark ? 0x707987 : 0x8993A1;
    palette.accent = dark ? 0x8993A0 : 0x5F6B7A;
    // The native skin uses a transparent selected fill and distinguishes the
    // row by text alone. IBus can express that text distinction directly.
    palette.selected = std::nullopt;
    palette.selected_text = dark ? 0xF1F3F5 : 0x111827;
    palette.selected_number = palette.selected_text;
    palette.border = dark ? 0x30353B : 0xE2E5E9;
    palette.border_alpha = 0xFF;
  } else if (skin == "willow_green") {
    palette.surface = dark ? 0x2D2F2E : 0xF4F5F3;
    palette.text = dark ? 0xD8DBD8 : 0x343936;
    palette.number = dark ? 0xA6ABA7 : 0x686F6A;
    palette.accent = dark ? 0x65C98D : 0x58B980;
    palette.selected = palette.accent;
    palette.selected_text = palette.selected_number = 0xFFFFFF;
    palette.border = 0;
    palette.border_alpha = 0;
    palette.border_width = 0;
  }
  return palette;
}

inline std::uint32_t candidate_builtin_accent(std::string_view skin,
                                              bool dark) {
  return candidate_builtin_palette(skin, dark).accent;
}

// IBus auxiliary text has no native caret geometry. When the displayed
// candidate preedit is the Engine's ASCII editing text, a plain-text marker is
// the least surprising Linux equivalent of the Windows candidate caret. Do
// not guess when the host has transformed the displayed text or the offset is
// invalid.
inline std::string candidate_preedit_with_caret(std::string_view preedit,
                                                std::string_view editing,
                                                std::size_t caret) {
  std::string result(preedit);
  if (preedit.empty() || preedit != editing || caret > preedit.size())
    return result;
  result.insert(caret, "|");
  return result;
}

} // namespace msime::linux_host

#pragma once
#include <cctype>
#include <cstdint>
#include <optional>
#include <sstream>
#include <string>

namespace msime::windows {
// Candidate colors ported from the shipped presenter. Skin manifests carry CSS
// strings because the settings page renders them in a WebView, so a native
// presenter parses the same subset and keeps its own value for anything it
// cannot represent. Channels are straight alpha in [0,1]; the renderer
// converts to its own color type, leaving this header free of Direct2D.
struct CandidateColor {
  float r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
  friend bool operator==(const CandidateColor &left,
                         const CandidateColor &right) {
    return left.r == right.r && left.g == right.g && left.b == right.b &&
           left.a == right.a;
  }
};
inline constexpr CandidateColor candidate_rgb(uint32_t rgb,
                                              float alpha = 1.0f) {
  return {((rgb >> 16) & 0xFF) / 255.0f, ((rgb >> 8) & 0xFF) / 255.0f,
          (rgb & 0xFF) / 255.0f, alpha};
}
inline CandidateColor parse_css_color(const std::string &text,
                                      CandidateColor fallback) {
  auto space = [](unsigned char ch) { return std::isspace(ch) != 0; };
  size_t begin = 0, end = text.size();
  while (begin < end && space(static_cast<unsigned char>(text[begin])))
    ++begin;
  while (end > begin && space(static_cast<unsigned char>(text[end - 1])))
    --end;
  std::string value = text.substr(begin, end - begin);
  if (value.empty() || value == "auto" || value == "none")
    return fallback;
  // Fully transparent is a deliberate choice, not a missing value.
  if (value == "transparent")
    return {0.0f, 0.0f, 0.0f, 0.0f};
  if (value.rfind("rgba(", 0) == 0 || value.rfind("rgb(", 0) == 0) {
    const auto open = value.find('(');
    const auto close = value.rfind(')');
    if (open == std::string::npos || close == std::string::npos ||
        close <= open)
      return fallback;
    std::string inner = value.substr(open + 1, close - open - 1);
    for (char &ch : inner)
      if (ch == ',')
        ch = ' ';
    std::istringstream stream(inner);
    float r = 0.0f, g = 0.0f, b = 0.0f, a = 1.0f;
    if (!(stream >> r >> g >> b))
      return fallback;
    stream >> a;
    return {r / 255.0f, g / 255.0f, b / 255.0f, a};
  }
  if (!value.empty() && value.front() == '#')
    value.erase(value.begin());
  for (char ch : value)
    if (!std::isxdigit(static_cast<unsigned char>(ch)))
      return fallback;
  auto channel = [&value](size_t index, size_t width) {
    const auto digits = width == 1 ? std::string(2, value[index])
                                   : value.substr(index, 2);
    return static_cast<uint32_t>(std::stoul(digits, nullptr, 16));
  };
  if (value.size() == 3)
    return {channel(0, 1) / 255.0f, channel(1, 1) / 255.0f,
            channel(2, 1) / 255.0f, 1.0f};
  if (value.size() == 6)
    return {channel(0, 2) / 255.0f, channel(2, 2) / 255.0f,
            channel(4, 2) / 255.0f, 1.0f};
  if (value.size() == 8)
    return {channel(0, 2) / 255.0f, channel(2, 2) / 255.0f,
            channel(4, 2) / 255.0f, channel(6, 2) / 255.0f};
  return fallback;
}
// Optional overrides as they arrive from the shared skin catalog. An absent
// or unparsable entry keeps the built-in value.
struct CandidatePaletteOverrides {
  std::optional<std::string> accent, selected, hover, surface, border, text,
      number;
  std::optional<bool> show_selected_bar;
};
struct CandidatePalette {
  CandidateColor surface = candidate_rgb(0x202020);
  CandidateColor border = candidate_rgb(0x9B9B9B, 0.18f);
  CandidateColor text = candidate_rgb(0xE9E8E8);
  CandidateColor number = candidate_rgb(0xE9E8E8, 0.616f);
  CandidateColor selected = candidate_rgb(0x3E3E3E, 0.725f);
  CandidateColor hover = candidate_rgb(0x414141);
  CandidateColor accent = candidate_rgb(0x6B69D6);
  float radius = 6.0f;
  float border_width = 1.5f;
  float container_padding = 5.0f;
  float item_radius = 4.0f;
  bool show_selected_bar = true;
};
// Built-in tokens. The defaults above are the shipped fluent dark values; the
// light branch replaces only the colors the shipped presenter overrides.
inline CandidatePalette candidate_light_palette() {
  CandidatePalette palette;
  palette.surface = candidate_rgb(0xFFFFFF);
  palette.border = {0.0f, 0.0f, 0.0f, 0.12f};
  palette.text = candidate_rgb(0x1A1A1A);
  palette.number = candidate_rgb(0x1A1A1A, 0.55f);
  palette.selected = candidate_rgb(0xE8E8E8);
  palette.hover = candidate_rgb(0xECECEC);
  return palette;
}
inline CandidatePalette
candidate_palette(const CandidatePaletteOverrides &overrides,
                  CandidatePalette palette = {}) {
  auto apply = [](const std::optional<std::string> &value,
                  CandidateColor &target) {
    if (value && !value->empty())
      target = parse_css_color(*value, target);
  };
  apply(overrides.accent, palette.accent);
  apply(overrides.selected, palette.selected);
  apply(overrides.hover, palette.hover);
  apply(overrides.surface, palette.surface);
  apply(overrides.border, palette.border);
  apply(overrides.text, palette.text);
  apply(overrides.number, palette.number);
  if (overrides.show_selected_bar)
    palette.show_selected_bar = *overrides.show_selected_bar;
  return palette;
}
} // namespace msime::windows

#pragma once

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <optional>
#include <sstream>
#include <string>
#include <string_view>
#include <system_error>

#include "CandidateColors.h"

namespace msime::linux_host {

// Fcitx5's classic UI draws the candidate list from a named theme. MSIME publishes its palette as a theme of its own, so the list looks the same as on IBus and Windows, while a theme the user picked in fcitx5-configtool is never replaced: only Fcitx5's stock themes, or MSIME's own, are taken over.
inline constexpr std::string_view kFcitxCandidateTheme = "msime";

inline bool fcitx_theme_replaceable(std::string_view current) {
  return current.empty() || current == "default" || current == "default-dark" ||
         current == kFcitxCandidateTheme;
}

inline std::string fcitx_theme_color(std::uint32_t rgb, bool transparent = false) {
  char buffer[10];
  std::snprintf(buffer, sizeof buffer, transparent ? "#%06x00" : "#%06x", rgb & 0xffffffu);
  return buffer;
}

// The classic UI theme format has no label or accent colour and no hover state separate from the highlight, so the candidate number follows the text and the accent is not drawn; everything the format can carry comes from the same resolution IBus uses. Without a selected fill (the graphite skin) the highlight is transparent and the selected row is told apart by its text colour alone, as on Windows.
inline std::string fcitx_candidate_theme(const CandidateColors &colors) {
  const auto surface = colors.background.value_or(0xffffffu);
  const auto text = colors.text.value_or(contrasting_color(surface).value_or(0));
  const auto selected_text = colors.selected_text.value_or(text);
  const auto highlight = colors.selected ? fcitx_theme_color(*colors.selected) : fcitx_theme_color(surface, true);
  // The classic UI clips the border to the smallest background margin and draws it inside that margin, so the margins grow with the width, and the content margin with them so the highlight never covers the outline. At the widths the skins use (0 or 1) both stay at 2 and the list keeps its layout.
  const int border_width = colors.border ? std::max(0, colors.border_width) : 0;
  const auto border = border_width > 0 ? fcitx_theme_color(*colors.border) : fcitx_theme_color(surface, true);
  const auto edge = std::to_string(std::max(2, border_width + 1));
  const auto margin = "Left=" + edge + "\nRight=" + edge + "\nTop=" + edge + "\nBottom=" + edge + "\n\n";
  std::ostringstream conf;
  conf << "[Metadata]\n"
          "Name=MSIME\n"
          "Version=1\n"
          "Author=MSIME\n"
          "Description=Generated from the MSIME candidate settings; edits are replaced when they change\n"
          "ScaleWithDPI=True\n\n"
          "[InputPanel]\n"
       << "NormalColor=" << fcitx_theme_color(text) << "\n"
       << "HighlightCandidateColor=" << fcitx_theme_color(selected_text) << "\n"
       << "HighlightColor=" << fcitx_theme_color(selected_text) << "\n"
       << "HighlightBackgroundColor=" << highlight << "\n"
       << "EnableBlur=False\n"
          "FullWidthHighlight=True\n"
          "Spacing=0\n\n"
          "[InputPanel/Background]\n"
       << "Color=" << fcitx_theme_color(surface) << "\n"
       << "BorderColor=" << border << "\n"
       << "BorderWidth=" << border_width << "\n\n"
       << "[InputPanel/Background/Margin]\n" << margin
       << "[InputPanel/ContentMargin]\n" << margin
       << "[InputPanel/TextMargin]\nLeft=6\nRight=6\nTop=4\nBottom=4\n\n"
          "[InputPanel/Highlight]\n"
       << "Color=" << highlight << "\n\n"
       << "[InputPanel/Highlight/Margin]\nLeft=6\nRight=6\nTop=4\nBottom=4\n\n"
          "[Menu]\n"
       << "NormalColor=" << fcitx_theme_color(text) << "\n"
       << "HighlightCandidateColor=" << fcitx_theme_color(selected_text) << "\n\n"
       << "[Menu/Background]\n"
       << "Color=" << fcitx_theme_color(surface) << "\n\n"
       << "[Menu/Highlight]\n"
       << "Color=" << highlight << "\n\n"
       << "[Menu/Separator]\n"
       << "Color=" << fcitx_theme_color(text) << "\n\n"
       << "[Menu/ContentMargin]\nLeft=2\nRight=2\nTop=2\nBottom=2\n\n"
          "[Menu/TextMargin]\nLeft=6\nRight=6\nTop=4\nBottom=4\n";
  return conf.str();
}

// Where Fcitx5 looks for a user theme: $XDG_DATA_HOME/fcitx5/themes/<name>/theme.conf. A relative XDG value is ignored, as the specification requires.
inline std::optional<std::filesystem::path> fcitx_theme_file(const char *xdg_data_home, const char *home) {
  std::filesystem::path base;
  if (xdg_data_home && std::filesystem::path(xdg_data_home).is_absolute())
    base = xdg_data_home;
  else if (home && std::filesystem::path(home).is_absolute())
    base = std::filesystem::path(home) / ".local/share";
  else
    return std::nullopt;
  return base / "fcitx5/themes" / std::string(kFcitxCandidateTheme) / "theme.conf";
}

// Replace the theme file atomically, leaving it untouched when it already holds the content. Returns whether the file now holds it.
inline bool write_fcitx_theme(const std::filesystem::path &file, const std::string &content) {
  std::error_code error;
  {
    std::ifstream current(file, std::ios::binary);
    if (current && std::string(std::istreambuf_iterator<char>(current), {}) == content) return true;
  }
  std::filesystem::create_directories(file.parent_path(), error);
  if (error) return false;
  auto staged = file;
  staged += ".new";
  {
    std::ofstream out(staged, std::ios::binary | std::ios::trunc);
    if (!(out << content) || !out.flush()) return false;
  }
  std::filesystem::rename(staged, file, error);
  if (error) {
    std::filesystem::remove(staged, error);
    return false;
  }
  return true;
}

}  // namespace msime::linux_host

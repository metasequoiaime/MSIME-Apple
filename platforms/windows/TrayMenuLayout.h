#pragma once
#include <algorithm>
#include <cstddef>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace msime::windows {
// Tray menu contents and geometry, ported from the shipped presenter. This
// header decides what the menu offers and where each row sits; drawing and
// window placement stay with the renderer, so the rules are testable without
// a desktop.
enum class TrayMenuCommand {
  ToggleFloatingToolbar,
  OpenEmojiPanel,
  OpenHandwritingPanel,
  OpenKeyboardPanel,
  ToggleVoiceInput,
  OpenSettings,
  OpenAbout,
};
struct TrayMenuItem {
  TrayMenuCommand command;
  std::string label;
  // Only the toolbar row carries a switch; the rest open a surface.
  bool toggle = false;
  // A row whose host capability is missing is shown disabled rather than
  // silently doing nothing when clicked.
  bool available = true;
  bool checked = false;
};
// Which surfaces this host can actually open. Anything absent stays visible
// but disabled, matching how the shipped menu never hides its entries.
struct TrayMenuCapabilities {
  bool floating_toolbar = true;
  bool emoji_panel = false;
  bool handwriting_panel = false;
  bool keyboard_panel = false;
  bool voice_input = false;
  bool settings = false;
};
inline std::vector<TrayMenuItem>
tray_menu_items(const TrayMenuCapabilities &capabilities,
                bool floating_toolbar_visible) {
  return {
      {TrayMenuCommand::ToggleFloatingToolbar, "悬浮工具栏", true,
       capabilities.floating_toolbar, floating_toolbar_visible},
      {TrayMenuCommand::OpenEmojiPanel, "表情/符号面板", false,
       capabilities.emoji_panel, false},
      {TrayMenuCommand::OpenHandwritingPanel, "手写识别板", false,
       capabilities.handwriting_panel, false},
      {TrayMenuCommand::OpenKeyboardPanel, "屏幕键盘", false,
       capabilities.keyboard_panel, false},
      {TrayMenuCommand::ToggleVoiceInput, "语音输入", false,
       capabilities.voice_input, false},
      {TrayMenuCommand::OpenSettings, "设置", false, capabilities.settings,
       false},
      {TrayMenuCommand::OpenAbout, "关于", false, capabilities.settings, false},
  };
}
struct TrayMenuMetrics {
  double width = 220.0;
  double row_height = 36.0;
  double padding = 6.0;
  double radius = 8.0;
  double border_width = 1.0;
};
struct TrayMenuSize {
  double width, height;
};
inline TrayMenuSize tray_menu_size(size_t rows, const TrayMenuMetrics &metrics) {
  if (rows == 0 || rows > 16 || metrics.width <= 0.0 ||
      metrics.row_height <= 0.0 || metrics.padding < 0.0)
    throw std::invalid_argument("Invalid tray menu metrics");
  return {metrics.width,
          metrics.padding * 2.0 +
              metrics.row_height * static_cast<double>(rows)};
}
struct TrayMenuRow {
  double top, bottom;
};
inline TrayMenuRow tray_menu_row(size_t index, size_t rows,
                                 const TrayMenuMetrics &metrics) {
  if (index >= rows)
    throw std::invalid_argument("Invalid tray menu row");
  const double top =
      metrics.padding + metrics.row_height * static_cast<double>(index);
  return {top, top + metrics.row_height};
}
// A click selects the row it landed on, and never a disabled one.
inline std::optional<size_t>
tray_menu_hit(double x, double y, const std::vector<TrayMenuItem> &items,
              const TrayMenuMetrics &metrics) {
  if (items.empty())
    return std::nullopt;
  const auto size = tray_menu_size(items.size(), metrics);
  if (x < 0.0 || y < 0.0 || x >= size.width || y >= size.height)
    return std::nullopt;
  for (size_t index = 0; index < items.size(); ++index) {
    const auto row = tray_menu_row(index, items.size(), metrics);
    if (y >= row.top && y < row.bottom)
      return items[index].available ? std::optional<size_t>(index)
                                    : std::nullopt;
  }
  return std::nullopt;
}
// Anchor the card under the tray icon, kept inside the work area.
struct TrayMenuBounds {
  int x, y, width, height;
};
inline TrayMenuBounds tray_menu_bounds(int icon_center_x, int icon_top,
                                       int left, int top, int right,
                                       int bottom, unsigned dpi,
                                       const TrayMenuSize &size) {
  if (dpi < 48 || dpi > 960 || right <= left || bottom <= top)
    throw std::invalid_argument("Invalid tray menu placement");
  const double scale = static_cast<double>(dpi) / 96.0;
  const auto width = static_cast<int>(size.width * scale + 0.5);
  const auto height = static_cast<int>(size.height * scale + 0.5);
  const int available_width = right - left;
  const int available_height = bottom - top;
  const int placed_width = (std::min)(width, available_width);
  const int placed_height = (std::min)(height, available_height);
  // The menu opens above the icon, which sits in the tray at the bottom.
  const int desired_y = icon_top - placed_height;
  return {(std::clamp)(icon_center_x - placed_width / 2, left,
                       right - placed_width),
          (std::clamp)(desired_y, top, bottom - placed_height), placed_width,
          placed_height};
}
} // namespace msime::windows

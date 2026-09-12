#include "TrayMenuLayout.h"
#include <cmath>
#include <stdexcept>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Tray menu layout validation failed");
}
bool near(double value, double expected) {
  return std::fabs(value - expected) < 0.001;
}
bool rejected(void (*action)()) {
  try {
    action();
  } catch (const std::invalid_argument &) {
    return true;
  }
  return false;
}
int main() {
  // The menu always offers the shipped entries, in the shipped order.
  TrayMenuCapabilities all{true, true, true, true, true, true};
  const auto items = tray_menu_items(all, false);
  require(items.size() == 7);
  require(items[0].command == TrayMenuCommand::ToggleFloatingToolbar &&
          items[0].label == "悬浮工具栏" && items[0].toggle);
  require(items[1].label == "表情/符号面板" && !items[1].toggle);
  require(items[2].label == "手写识别板");
  require(items[3].label == "屏幕键盘");
  require(items[4].label == "语音输入");
  require(items[5].label == "设置");
  require(items[6].label == "关于");

  // Only the toolbar row carries the switch, and it follows the live state.
  require(!items[0].checked);
  require(tray_menu_items(all, true)[0].checked);
  for (size_t index = 1; index < items.size(); ++index)
    require(!items[index].checked && !items[index].toggle);

  // A host without a capability shows the row disabled rather than hiding it
  // or accepting a click that would do nothing.
  TrayMenuCapabilities server_only;
  const auto limited = tray_menu_items(server_only, true);
  require(limited.size() == items.size());
  require(limited[0].available && !limited[1].available &&
          !limited[4].available && !limited[5].available &&
          !limited[6].available);

  const TrayMenuMetrics metrics;
  const auto size = tray_menu_size(items.size(), metrics);
  require(near(size.width, 220.0));
  require(near(size.height, metrics.padding * 2.0 + metrics.row_height * 7.0));
  const auto first = tray_menu_row(0, items.size(), metrics);
  const auto second = tray_menu_row(1, items.size(), metrics);
  require(near(first.top, metrics.padding));
  require(near(first.bottom, first.top + metrics.row_height));
  require(near(second.top, first.bottom));
  require(rejected([] { (void)tray_menu_row(7, 7, TrayMenuMetrics{}); }));
  require(rejected([] { (void)tray_menu_size(0, TrayMenuMetrics{}); }));
  require(rejected([] { (void)tray_menu_size(17, TrayMenuMetrics{}); }));

  // Clicks land on the row that was drawn; disabled rows swallow theirs.
  auto hit = [&](double x, double y) {
    return tray_menu_hit(x, y, items, metrics);
  };
  require(hit(10.0, first.top + 1.0) == std::optional<size_t>(0));
  require(hit(10.0, second.top + 1.0) == std::optional<size_t>(1));
  require(!hit(10.0, metrics.padding / 2.0));
  require(!hit(10.0, size.height));
  require(!hit(-1.0, first.top + 1.0) && !hit(size.width, first.top + 1.0));
  require(!tray_menu_hit(10.0, second.top + 1.0, limited, metrics));
  require(tray_menu_hit(10.0, first.top + 1.0, limited, metrics) ==
          std::optional<size_t>(0));

  // The card opens above the tray icon and stays inside the work area.
  const auto placed =
      tray_menu_bounds(1800, 1040, 0, 0, 1920, 1040, 96, size);
  require(placed.width == 220 && placed.height == static_cast<int>(size.height + 0.5));
  require(placed.y == 1040 - placed.height);
  require(placed.x == 1800 - placed.width / 2);
  // A corner icon cannot push the card off screen.
  const auto clamped = tray_menu_bounds(1915, 1040, 0, 0, 1920, 1040, 96, size);
  require(clamped.x == 1920 - clamped.width);
  const auto scaled = tray_menu_bounds(960, 1040, 0, 0, 1920, 1040, 192, size);
  require(scaled.width == 440);
  // A work area smaller than the card clamps instead of overflowing.
  const auto tiny = tray_menu_bounds(50, 80, 0, 0, 100, 80, 96, size);
  require(tiny.width == 100 && tiny.height == 80 && tiny.x == 0 && tiny.y == 0);
  require(rejected([] {
    (void)tray_menu_bounds(0, 0, 0, 0, 0, 0, 96, TrayMenuSize{220.0, 100.0});
  }));
  require(rejected([] {
    (void)tray_menu_bounds(0, 0, 0, 0, 100, 100, 20, TrayMenuSize{220.0, 100.0});
  }));
}

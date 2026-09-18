#pragma once

#include <algorithm>

namespace msime::linux_host {

struct WaveOverlayWorkArea {
  int x = 0;
  int y = 0;
  int width = 0;
  int height = 0;
};

struct WaveOverlayPosition {
  int x = 0;
  int y = 0;
};

constexpr int kWaveOverlayBottomMargin = 24;

constexpr WaveOverlayPosition
wave_overlay_bottom_center(WaveOverlayWorkArea work_area, int overlay_width,
                           int overlay_height,
                           int bottom_margin = kWaveOverlayBottomMargin) {
  const auto width = std::max(0, overlay_width);
  const auto height = std::max(0, overlay_height);
  const auto margin = std::max(0, bottom_margin);
  const auto x = work_area.width > width
                     ? work_area.x + (work_area.width - width) / 2
                     : work_area.x;
  const auto y = work_area.height >= height + margin
                     ? work_area.y + work_area.height - height - margin
                     : work_area.y;
  return {x, y};
}

} // namespace msime::linux_host

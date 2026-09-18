#pragma once

#include <windows.h>

namespace msime::windows {
struct WaveOverlayMonitorMetrics {
  RECT monitor{};
  RECT work{};
};

bool wave_overlay_monitor_metrics(WaveOverlayMonitorMetrics *metrics);
} // namespace msime::windows

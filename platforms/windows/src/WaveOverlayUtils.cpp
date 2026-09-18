#include "WaveOverlayUtils.h"

namespace msime::windows {
bool wave_overlay_monitor_metrics(WaveOverlayMonitorMetrics *metrics) {
  if (!metrics)
    return false;
  const HWND foreground = GetForegroundWindow();
  const HMONITOR monitor = MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!monitor || !GetMonitorInfoW(monitor, &info))
    return false;
  metrics->monitor = info.rcMonitor;
  metrics->work = info.rcWork;
  return true;
}
} // namespace msime::windows

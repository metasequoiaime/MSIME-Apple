#include "WaveOverlayUtils.h"

#include <shellapi.h>

namespace msime::windows {
int wave_overlay_taskbar_height() {
  APPBARDATA data{};
  data.cbSize = sizeof(data);
  if (!SHAppBarMessage(ABM_GETTASKBARPOS, &data))
    return 0;
  return data.uEdge == ABE_TOP || data.uEdge == ABE_BOTTOM
             ? data.rc.bottom - data.rc.top
             : data.rc.right - data.rc.left;
}

RECT wave_overlay_monitor() {
  RECT coordinates{};
  const HWND foreground = GetForegroundWindow();
  const HMONITOR monitor = MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  if (monitor && GetMonitorInfoW(monitor, &info))
    coordinates = info.rcMonitor;
  return coordinates;
}
} // namespace msime::windows

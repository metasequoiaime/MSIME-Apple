#pragma once

#include <windows.h>

namespace msime::windows {
// Everything the voice bar needs about the monitor it is about to appear on,
// resolved once so that placement and scale cannot disagree by landing on two
// different monitors.
struct WaveOverlayMonitorMetrics {
  // The whole screen. The bar is centred horizontally against this so a
  // taskbar docked left or right does not push it off centre.
  RECT monitor{};
  // The work area, which already excludes a taskbar on any edge. The bar sits
  // just above its bottom.
  RECT work{};
  // Effective DPI of that same monitor, never zero.
  UINT dpi = 96;
};

bool wave_overlay_monitor_metrics(WaveOverlayMonitorMetrics *metrics);

// Per-monitor awareness for one geometry operation, restoring the caller's
// thread context afterwards. Without it `GetMonitorInfoW` reports virtualised
// coordinates and `GetDpiForMonitor` is documented to answer 96 for a
// DPI-unaware caller, which would silently defeat every calculation here.
// Unlike the candidate window's scope this one never throws: the voice bar is
// not worth failing a recognition over, and an unavailable context simply
// leaves the legacy behaviour in place.
struct WaveOverlayDpiScope {
  DPI_AWARENESS_CONTEXT previous;
  WaveOverlayDpiScope()
      : previous(SetThreadDpiAwarenessContext(
            DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {}
  ~WaveOverlayDpiScope() {
    if (previous)
      SetThreadDpiAwarenessContext(previous);
  }
  WaveOverlayDpiScope(const WaveOverlayDpiScope &) = delete;
  WaveOverlayDpiScope &operator=(const WaveOverlayDpiScope &) = delete;
};
} // namespace msime::windows

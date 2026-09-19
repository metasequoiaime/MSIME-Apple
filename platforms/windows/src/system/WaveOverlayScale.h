#pragma once

namespace msime::windows {
// The unscaled baseline every Win32 DPI API is expressed against.
inline constexpr unsigned int kWaveOverlayBaselineDpi = 96;

// Decide the DPI the voice bar is sized and rendered with.
//
// Placement anchors on the foreground window's monitor, so the scale has to be
// read from that same monitor. `GetDpiForWindow` answers for the overlay's own
// window instead: on a mixed-DPI desktop that is a different monitor until
// Windows delivers WM_DPICHANGED - which arrives after the move, not before it
// - and across a resolution switch it can still report the previous value.
//
// `monitor_dpi` is `GetDpiForMonitor(MDT_EFFECTIVE_DPI)` for that monitor and
// `system_dpi` is `GetDpiForSystem()`; either is 0 when its query failed. A
// zero must never reach the size arithmetic, which would collapse the bar to
// nothing, so the baseline is the last resort rather than an error.
inline unsigned int wave_overlay_dpi(unsigned int monitor_dpi,
                                     unsigned int system_dpi) {
  if (monitor_dpi)
    return monitor_dpi;
  if (system_dpi)
    return system_dpi;
  return kWaveOverlayBaselineDpi;
}

inline float wave_overlay_scale(unsigned int dpi) {
  return static_cast<float>(wave_overlay_dpi(dpi, 0)) /
         static_cast<float>(kWaveOverlayBaselineDpi);
}
} // namespace msime::windows

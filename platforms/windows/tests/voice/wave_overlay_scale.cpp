#include "../../src/system/WaveOverlayScale.h"
#include <cassert>

int main() {
  using msime::windows::kWaveOverlayBaselineDpi;
  using msime::windows::wave_overlay_dpi;
  using msime::windows::wave_overlay_scale;

  // The monitor's own answer wins whenever there is one.
  assert(wave_overlay_dpi(144, 96) == 144);
  assert(wave_overlay_dpi(96, 192) == 96);

  // GetDpiForMonitor is unavailable before Windows 8.1 and fails for a stale
  // HMONITOR; the system DPI still sizes the bar sensibly.
  assert(wave_overlay_dpi(0, 192) == 192);

  // Both queries failing must not leave a zero to multiply the bar's width by.
  assert(wave_overlay_dpi(0, 0) == kWaveOverlayBaselineDpi);

  assert(wave_overlay_scale(96) == 1.0f);
  assert(wave_overlay_scale(192) == 2.0f);
  assert(wave_overlay_scale(144) == 1.5f);
  assert(wave_overlay_scale(0) == 1.0f);
}

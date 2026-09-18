#include "../src/WaveOverlayPlacement.h"

#include <cassert>

int main() {
  using msime::linux_host::wave_overlay_bottom_center;
  using msime::linux_host::WaveOverlayWorkArea;

  const auto primary = wave_overlay_bottom_center({0, 0, 1920, 1080}, 420, 132);
  assert(primary.x == 750);
  assert(primary.y == 924);

  const auto negative =
      wave_overlay_bottom_center({-1920, 40, 1920, 1040}, 420, 132);
  assert(negative.x == -1170);
  assert(negative.y == 924);

  const auto narrow =
      wave_overlay_bottom_center({100, 200, 300, 100}, 420, 132);
  assert(narrow.x == 100);
  assert(narrow.y == 200);

  const auto custom_margin = wave_overlay_bottom_center(
      WaveOverlayWorkArea{10, -20, 800, 600}, 400, 100, 16);
  assert(custom_margin.x == 210);
  assert(custom_margin.y == 464);
}

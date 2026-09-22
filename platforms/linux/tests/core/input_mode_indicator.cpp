#include "../src/core/InputModeIndicator.h"

#include <cassert>

int main() {
  using msime::linux_host::input_mode_indicator;
  using Indicator = msime::linux_host::InputModeIndicator;

  assert(input_mode_indicator(true, false, false) == Indicator::Chinese);
  assert(input_mode_indicator(true, true, false) == Indicator::Japanese);
  assert(input_mode_indicator(false, false, false) == Indicator::English);
  // Direct input with the Japanese scheme selected types English.
  assert(input_mode_indicator(false, true, false) == Indicator::English);
  // CapsLock wins in every mode, as on the Windows language bar.
  assert(input_mode_indicator(true, false, true) == Indicator::CapsLock);
  assert(input_mode_indicator(true, true, true) == Indicator::CapsLock);
  assert(input_mode_indicator(false, false, true) == Indicator::CapsLock);
  return 0;
}

#include "input/TerminalDeactivationPolicy.h"
#include <cassert>

int main() {
  using msime::windows::terminal_deactivation_state_available;
  assert(terminal_deactivation_state_available(true, true));
  assert(!terminal_deactivation_state_available(false, true));
  assert(!terminal_deactivation_state_available(true, false));
  assert(!terminal_deactivation_state_available(false, false));
}

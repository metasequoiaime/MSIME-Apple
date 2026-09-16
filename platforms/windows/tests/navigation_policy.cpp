#include "../NavigationPolicy.h"
#include <cassert>
int main() {
  msime::windows::FanyImeNamedpipeData packet{};
  packet.event_type = FanyImePipeEventType::KeyEvent;
  packet.keycode = 0xBD;
  msime::windows::NavigationBindings bindings{true, false, false, false, false, false, false};
  assert(msime::windows::navigation_action(packet, bindings, false).has_value());
  assert(!msime::windows::navigation_action(packet, bindings, false, true).has_value());
}

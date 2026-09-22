#include "core/BackspaceHoldPolicy.h"
#include <stdexcept>

void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

int main() {
  msime::linux_host::BackspaceHoldPolicy hold;

  require(!hold.press(true), "the first composing press must reach the runtime");
  require(hold.armed(), "a composing press did not claim the physical hold");
  require(!hold.press(true), "repeats must keep editing while composition remains");
  require(hold.press(false), "a repeat leaked after clearing the composition");
  hold.release();
  require(!hold.armed(), "release did not return Backspace to the editor");
  require(!hold.press(false), "a fresh idle press was swallowed");

  require(!hold.press(true), "a second composing hold did not start");
  hold.reset();
  require(!hold.press(false), "focus/reset leaked ownership into another stroke");
}

#include "NativeCompose.h"
#include <xkbcommon/xkbcommon-keysyms.h>
#include <stdexcept>

int main() {
  setenv("LC_ALL", "C.UTF-8", 1);
  msime::linux_host::NativeCompose compose;
  auto require = [](bool value) {
    if (!value) throw std::runtime_error("System Compose boundary contract failed");
  };
  require(!compose.feed(XKB_KEY_e));
  require(compose.feed(XKB_KEY_dead_circumflex).has_value());
  require(compose.feed(XKB_KEY_e) == "ê");
  require(!compose.feed(XKB_KEY_e));
  require(compose.feed(XKB_KEY_Multi_key).has_value());
  require(compose.feed(XKB_KEY_apostrophe).has_value());
  require(compose.feed(XKB_KEY_e) == "é");
  require(!compose.feed(XKB_KEY_e));
  require(compose.feed(XKB_KEY_dead_circumflex).has_value());
  compose.reset();
  require(!compose.feed(XKB_KEY_e));
  require(compose.feed(XKB_KEY_Multi_key).has_value());
  require(compose.feed(XKB_KEY_Escape).has_value());
  require(!compose.feed(XKB_KEY_e));
}

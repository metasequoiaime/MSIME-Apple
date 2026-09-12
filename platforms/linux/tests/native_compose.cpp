#include "NativeCompose.h"
#include <xkbcommon/xkbcommon-keysyms.h>
#include <stdexcept>

int main(int argc, char **argv) {
  if (argc != 2) throw std::runtime_error("Isolated Compose fixture required");
  setenv("XCOMPOSEFILE", argv[1], 1);
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
  require(compose.feed(XKB_KEY_Multi_key).has_value());
  require(compose.feed(XKB_KEY_x).has_value());
  require(compose.feed(XKB_KEY_x) == "水杉😀");
  require(!compose.feed(XKB_KEY_e));
  // An invalid sequence is consumed once, then normal input resumes.
  require(compose.feed(XKB_KEY_Multi_key).has_value());
  require(compose.feed(XKB_KEY_F1).has_value());
  require(!compose.feed(XKB_KEY_e));
  // Native contexts must never share an in-progress sequence.
  msime::linux_host::NativeCompose other;
  require(compose.feed(XKB_KEY_dead_circumflex).has_value());
  require(!other.feed(XKB_KEY_e));
  require(compose.feed(XKB_KEY_e) == "ê");
}

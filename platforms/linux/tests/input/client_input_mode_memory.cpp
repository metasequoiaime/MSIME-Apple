#include "../src/core/ClientInputModeMemory.h"

#include <cassert>
#include <string>

int main() {
  msime::linux_host::ClientInputModeMemory memory;
  assert(memory.restore("editor-a", true));
  memory.remember("editor-a", false);
  assert(!memory.restore("editor-a", true));
  assert(memory.restore("editor-b", true));
  memory.remember("editor-b", false);
  assert(!memory.restore("editor-b", true));

  // An anonymous client shares one slot instead of losing the mode: it falls
  // back only until something is remembered for it.
  assert(memory.restore("", false) == false);
  assert(memory.restore("", true) == true);
  memory.remember("", true);
  assert(memory.restore("", false));
  memory.remember("", false);
  assert(!memory.restore("", true));
  assert(memory.restore("editor-c", true));

  for (std::size_t index = 0;
       index < msime::linux_host::ClientInputModeMemory::kMaxClients;
       ++index) {
    memory.remember("client-" + std::to_string(index), true);
  }
  memory.remember("client-overflow", false);
  // The bounded map clears before adding the overflow entry; it never grows
  // without limit and the newest client remains addressable.
  assert(!memory.restore("client-overflow", true));
  assert(memory.restore("client-0", true));
  memory.clear();
  assert(memory.restore("client-overflow", true));
  assert(memory.restore("", true));
  return 0;
}

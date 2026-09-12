#include "KeyRouterAdapter.h"
#include <cassert>
int main() {
  msime::linux_host::KeyRouterAdapter adapter;
  msime_client_key_event event{{1,2,3}, 0x41, 30, 0, 'a', false};
  assert(!adapter.accepts(event));
  adapter.set_lease(event.lease);
  assert(adapter.accepts(event));
  event.lease.epoch++;
  assert(!adapter.accepts(event));
  adapter.clear_lease();
  return 0;
}

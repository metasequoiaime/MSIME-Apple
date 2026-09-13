#include "KeyRouterAdapter.h"
#include <cassert>

int main() {
  msime::linux_host::KeyRouterAdapter adapter;
  msime_client_key_event event{{1, 2, 3}, 0x41, 30, 0, 'a', false};
  assert(adapter.check(event) == MSIME_CLIENT_KEY_DEFINITELY_NOT_SENT);

  adapter.set_lease(event.lease);
  assert(adapter.check(event) == MSIME_CLIENT_KEY_SENT);

  auto stale = event;
  stale.lease.epoch++;
  assert(adapter.check(stale) == MSIME_CLIENT_KEY_DEFINITELY_NOT_SENT);
  assert(!adapter.cancel(stale.lease));
  assert(adapter.check(event) == MSIME_CLIENT_KEY_SENT);

  assert(adapter.cancel(event.lease));
  assert(adapter.check(event) == MSIME_CLIENT_KEY_DEFINITELY_NOT_SENT);
  assert(!adapter.cancel(event.lease));
  return 0;
}

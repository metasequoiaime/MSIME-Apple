#pragma once
#include "msime_client.h"

namespace msime::linux_host {
class KeyRouterAdapter {
 public:
  static uint64_t lease_token(uint64_t client, uint64_t session) {
    return session != 0 ? session : client;
  }
  static uint32_t virtual_key(uint32_t key_symbol) {
    return key_symbol <= 0xff ? key_symbol : 0;
  }
  void set_lease(msime_client_focus_lease lease) { lease_ = lease; }
  void clear_lease() { lease_ = {}; }
  msime_client_key_dispatch_result check(const msime_client_key_event &event) const {
    if (!msime_client_key_event_valid(&event) || event.lease.client != lease_.client ||
        event.lease.epoch != lease_.epoch || event.lease.token != lease_.token)
      return MSIME_CLIENT_KEY_DEFINITELY_NOT_SENT;
    return MSIME_CLIENT_KEY_SENT;
  }
  bool cancel(msime_client_focus_lease lease) {
    // An all-zero lease is the sentinel for "no active route". Treat it as
    // invalid even when the adapter is already clear; otherwise a stale
    // focus-out callback could report a successful cancellation and mask a
    // routing lifetime bug.
    if (lease.client == 0 || lease.epoch == 0 || lease.token == 0 ||
        lease_.client == 0 || lease_.epoch == 0 || lease_.token == 0 ||
        lease.client != lease_.client || lease.epoch != lease_.epoch ||
        lease.token != lease_.token)
      return false;
    clear_lease();
    return true;
  }
  bool accepts(const msime_client_key_event &event) const {
    return check(event) == MSIME_CLIENT_KEY_SENT;
  }
 private:
  msime_client_focus_lease lease_{};
};
}  // namespace msime::linux_host

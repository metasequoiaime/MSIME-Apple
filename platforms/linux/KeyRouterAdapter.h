#pragma once
#include "msime_client.h"

namespace msime::linux_host {
class KeyRouterAdapter {
 public:
  void set_lease(msime_client_focus_lease lease) { lease_ = lease; }
  void clear_lease() { lease_ = {}; }
  bool cancel(msime_client_focus_lease lease) {
    if (lease.client != lease_.client || lease.epoch != lease_.epoch || lease.token != lease_.token)
      return false;
    clear_lease();
    return true;
  }
  bool accepts(const msime_client_key_event &event) const {
    return msime_client_key_event_valid(&event) && event.lease.client == lease_.client &&
           event.lease.epoch == lease_.epoch && event.lease.token == lease_.token;
  }
 private:
  msime_client_focus_lease lease_{};
};
}  // namespace msime::linux_host

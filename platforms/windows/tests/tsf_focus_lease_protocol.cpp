#include "TsfFocusLeaseProtocol.h"
#include <cassert>

int main() {
  using msime::windows::TsfFocusLeaseRequest;
  using msime::windows::valid_tsf_focus_lease_request;
  TsfFocusLeaseRequest request;
  request.client = 7;
  request.epoch = 11;
  request.token = 19;
  assert(valid_tsf_focus_lease_request(request));
  request.version_value = 2;
  assert(!valid_tsf_focus_lease_request(request));
}

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
  const auto frame = encode_tsf_focus_lease(request);
  const auto decoded = msime::windows::decode_tsf_focus_lease(frame);
  assert(valid_tsf_focus_lease_request(decoded));
  assert(decoded.client == 7 && decoded.epoch == 11 && decoded.token == 19);
  assert(frame[0] == 0x53 && frame[1] == 0x4c);
  request.version_value = 2;
  assert(!valid_tsf_focus_lease_request(request));
}

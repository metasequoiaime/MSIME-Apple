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
  assert(msime::windows::matches_tsf_focus_lease(decoded, 7, 11, 19));
  assert(!msime::windows::matches_tsf_focus_lease(decoded, 7, 11, 20));
  assert(!msime::windows::matches_tsf_focus_lease(decoded, 8, 11, 19));
  msime::windows::TsfFocusLeaseAuthenticator authenticator(7, 11, 19);
  assert(authenticator.authenticate(frame));
  authenticator.update(7, 11, 20);
  assert(!authenticator.authenticate(frame));
  assert(decoded.client == 7 && decoded.epoch == 11 && decoded.token == 19);
  assert(frame[0] == 0x53 && frame[1] == 0x4c);
  request.version_value = 2;
  assert(!valid_tsf_focus_lease_request(request));
  request.version_value = TsfFocusLeaseRequest::version;
  request.reserved = 1;
  assert(!valid_tsf_focus_lease_request(request));
  request.reserved = 0;
  request.magic_value ^= 1;
  assert(!valid_tsf_focus_lease_request(request));
  request.magic_value = TsfFocusLeaseRequest::magic;
  request.client = 0;
  assert(!valid_tsf_focus_lease_request(request));
}

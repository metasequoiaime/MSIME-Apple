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

  const auto complete_frame = encode_tsf_focus_lease(TsfFocusLeaseRequest{TsfFocusLeaseRequest::magic,
                                                                            TsfFocusLeaseRequest::version,
                                                                            0, 7, 11, 19});
  msime::windows::TsfFocusLeaseFrameAssembler assembler;
  assert(!assembler.complete() && assembler.size() == 0);
  assert(assembler.append(nullptr, 0));
  assert(!assembler.append(nullptr, 1));
  assert(assembler.size() == 0);
  assert(assembler.append(complete_frame.data(), 1));
  assert(assembler.size() == 1 && !assembler.complete());
  assert(assembler.append(complete_frame.data() + 1, complete_frame.size() - 1));
  assert(assembler.complete() && assembler.frame() == complete_frame);
  const auto before = assembler.frame();
  assert(!assembler.append(complete_frame.data(), 1));
  assert(assembler.frame() == before && assembler.size() == complete_frame.size());
  assembler.reset();
  assert(!assembler.complete() && assembler.size() == 0);
  assert(assembler.append(complete_frame.data(), complete_frame.size()));
  assert(assembler.complete());
}

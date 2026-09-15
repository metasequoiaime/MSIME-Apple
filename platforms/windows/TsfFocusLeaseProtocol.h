#pragma once

#include <cstdint>

namespace msime::windows {
// Separate versioned contract for the future TSF focus-lease request. It is
// deliberately not encoded as an existing FanyIme frame.
struct TsfFocusLeaseRequest {
  static constexpr std::uint32_t magic = 0x4D534C53; // MSLS
  static constexpr std::uint16_t version = 1;
  std::uint32_t magic_value = magic;
  std::uint16_t version_value = version;
  std::uint16_t reserved = 0;
  std::uint64_t client = 0;
  std::uint64_t epoch = 0;
  std::uint64_t token = 0;
};

constexpr bool valid_tsf_focus_lease_request(const TsfFocusLeaseRequest &request) {
  return request.magic_value == TsfFocusLeaseRequest::magic &&
         request.version_value == TsfFocusLeaseRequest::version &&
         request.reserved == 0 && request.client != 0 && request.epoch != 0 &&
         request.token != 0;
}
} // namespace msime::windows

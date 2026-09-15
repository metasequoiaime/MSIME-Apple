#pragma once

#include <cstdint>
#include <array>

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

using TsfFocusLeaseFrame = std::array<std::uint8_t, 32>;

constexpr void write_u16(std::uint8_t *out, std::uint16_t value) {
  out[0] = static_cast<std::uint8_t>(value);
  out[1] = static_cast<std::uint8_t>(value >> 8);
}
constexpr void write_u32(std::uint8_t *out, std::uint32_t value) {
  for (unsigned i = 0; i != 4; ++i) out[i] = static_cast<std::uint8_t>(value >> (i * 8));
}
constexpr void write_u64(std::uint8_t *out, std::uint64_t value) {
  for (unsigned i = 0; i != 8; ++i) out[i] = static_cast<std::uint8_t>(value >> (i * 8));
}
constexpr std::uint16_t read_u16(const std::uint8_t *in) {
  return static_cast<std::uint16_t>(in[0]) | static_cast<std::uint16_t>(in[1]) << 8;
}
constexpr std::uint32_t read_u32(const std::uint8_t *in) {
  std::uint32_t value = 0;
  for (unsigned i = 0; i != 4; ++i) value |= static_cast<std::uint32_t>(in[i]) << (i * 8);
  return value;
}
constexpr std::uint64_t read_u64(const std::uint8_t *in) {
  std::uint64_t value = 0;
  for (unsigned i = 0; i != 8; ++i) value |= static_cast<std::uint64_t>(in[i]) << (i * 8);
  return value;
}

constexpr TsfFocusLeaseFrame encode_tsf_focus_lease(const TsfFocusLeaseRequest &request) {
  TsfFocusLeaseFrame frame{};
  write_u32(frame.data(), request.magic_value);
  write_u16(frame.data() + 4, request.version_value);
  write_u16(frame.data() + 6, request.reserved);
  write_u64(frame.data() + 8, request.client);
  write_u64(frame.data() + 16, request.epoch);
  write_u64(frame.data() + 24, request.token);
  return frame;
}

constexpr TsfFocusLeaseRequest decode_tsf_focus_lease(const TsfFocusLeaseFrame &frame) {
  return {read_u32(frame.data()), read_u16(frame.data() + 4), read_u16(frame.data() + 6),
          read_u64(frame.data() + 8), read_u64(frame.data() + 16), read_u64(frame.data() + 24)};
}

constexpr bool valid_tsf_focus_lease_request(const TsfFocusLeaseRequest &request) {
  return request.magic_value == TsfFocusLeaseRequest::magic &&
         request.version_value == TsfFocusLeaseRequest::version &&
         request.reserved == 0 && request.client != 0 && request.epoch != 0 &&
         request.token != 0;
}
} // namespace msime::windows

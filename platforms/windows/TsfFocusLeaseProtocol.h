#pragma once

#include <cstdint>
#include <cstddef>
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
static_assert(TsfFocusLeaseFrame{}.size() == 32);

class TsfFocusLeaseFrameAssembler final {
public:
  constexpr bool append(const std::uint8_t *data, std::size_t size) {
    if (size > TsfFocusLeaseFrame{}.size() - filled_) return false;
    for (std::size_t i = 0; i != size; ++i) frame_[filled_ + i] = data[i];
    filled_ += size;
    return true;
  }

  constexpr bool complete() const { return filled_ == frame_.size(); }
  constexpr const TsfFocusLeaseFrame &frame() const { return frame_; }
  constexpr std::size_t size() const { return filled_; }
  constexpr void reset() { frame_ = {}; filled_ = 0; }

private:
  TsfFocusLeaseFrame frame_{};
  std::size_t filled_ = 0;
};

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

// Authentication gate used after transport identity and registration
// generation have been resolved by the Server. A syntactically valid frame is
// not sufficient: every lease component must still match the current owner.
constexpr bool matches_tsf_focus_lease(const TsfFocusLeaseRequest &request,
                                       std::uint64_t client,
                                       std::uint64_t epoch,
                                       std::uint64_t token) {
  return valid_tsf_focus_lease_request(request) && client != 0 && epoch != 0 &&
         token != 0 && request.client == client && request.epoch == epoch &&
         request.token == token;
}

class TsfFocusLeaseAuthenticator final {
public:
  constexpr TsfFocusLeaseAuthenticator() = default;
  constexpr explicit TsfFocusLeaseAuthenticator(std::uint64_t client,
                                                 std::uint64_t epoch,
                                                 std::uint64_t token)
      : client_(client), epoch_(epoch), token_(token) {}

  constexpr void update(std::uint64_t client, std::uint64_t epoch,
                        std::uint64_t token) {
    client_ = client;
    epoch_ = epoch;
    token_ = token;
  }

  constexpr bool authenticate(const TsfFocusLeaseFrame &frame) const {
    return matches_tsf_focus_lease(decode_tsf_focus_lease(frame), client_, epoch_, token_);
  }

private:
  std::uint64_t client_ = 0;
  std::uint64_t epoch_ = 0;
  std::uint64_t token_ = 0;
};
} // namespace msime::windows

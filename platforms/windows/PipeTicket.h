#pragma once
#include <array>
#include <cstdint>

namespace msime::windows {
// Transport registration generations, not Engine candidate/focus epochs.
struct PipeTicket {
  uint64_t client = 0;
  std::array<uint64_t, 3> generations{};
};
inline bool same_ticket(const PipeTicket &a, const PipeTicket &b) {
  return a.client == b.client && a.generations == b.generations;
}
} // namespace msime::windows

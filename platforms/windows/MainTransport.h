#pragma once
#include "PipeTicket.h"
#include "windows_ipc.h"
#include <optional>
#include <vector>

namespace msime::windows {
// The native implementation is PipeMainTransport. The seam allows the same
// session loop to execute against deterministic transport tests on other OSes.
class MainTransport {
public:
  virtual ~MainTransport() = default;
  // Thread-safe registration check only; must not perform pipe I/O.
  virtual bool current(const PipeTicket &ticket) = 0;
  virtual std::optional<FanyImeNamedpipeData>
  read(const PipeTicket &ticket) = 0;
  // Complete write only; false includes uncertain delivery. No retries.
  virtual bool send(const PipeTicket &ticket, uint32_t role,
                    const std::vector<uint8_t> &frame) = 0;
  virtual void close(const PipeTicket &ticket) noexcept = 0;
};
} // namespace msime::windows

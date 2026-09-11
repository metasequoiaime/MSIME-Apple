#pragma once
#include "MainTransport.h"
#include "PipeRegistry.h"

namespace msime::windows {
class PipeMainTransport final : public MainTransport {
public:
  PipeMainTransport(PipeRegistry &registry, DWORD write_timeout);
  bool current(const PipeTicket &ticket) override;
  bool try_current(const PipeTicket &ticket) override;
  std::optional<FanyImeNamedpipeData> read(const PipeTicket &ticket) override;
  KeyEventSendResult send(const PipeTicket &ticket, uint32_t role,
                          const std::vector<uint8_t> &frame) override;
  void close(const PipeTicket &ticket) noexcept override;

private:
  PipeRegistry &registry_;
  DWORD timeout_;
};
} // namespace msime::windows

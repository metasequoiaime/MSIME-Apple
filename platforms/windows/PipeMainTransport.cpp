#include "PipeMainTransport.h"
#include <cstring>
#include <stdexcept>

namespace msime::windows {
PipeMainTransport::PipeMainTransport(PipeRegistry &registry, DWORD timeout)
    : registry_(registry), timeout_(timeout) {
  if (!timeout || timeout == INFINITE)
    throw std::invalid_argument("Invalid session write timeout");
}
bool PipeMainTransport::current(const PipeTicket &ticket) {
  return registry_.is_current(ticket);
}
bool PipeMainTransport::try_current(const PipeTicket &ticket) {
  return registry_.try_is_current(ticket);
}
std::optional<FanyImeNamedpipeData>
PipeMainTransport::read(const PipeTicket &ticket) {
  auto result = registry_.read_main(ticket);
  if (!result.complete())
    return std::nullopt;
  FanyImeNamedpipeData packet{};
  std::memcpy(&packet, result.frame.data(), sizeof(packet));
  return packet;
}
KeyEventSendResult PipeMainTransport::send(const PipeTicket &ticket,
                                           uint32_t role,
                                           const std::vector<uint8_t> &frame) {
  const auto result = registry_.send(ticket, role, frame, timeout_);
  if (result.complete()) return KeyEventSendResult::Sent;
  return result.delivery_uncertain ? KeyEventSendResult::DeliveryAmbiguous
                                   : KeyEventSendResult::DefinitelyNotSent;
}
void PipeMainTransport::close(const PipeTicket &ticket) noexcept {
  registry_.remove(ticket, FanyImePipeRole::Main);
}
} // namespace msime::windows

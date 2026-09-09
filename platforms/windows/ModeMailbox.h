#pragma once
#include "FocusGate.h"
#include "MainTransport.h"

namespace msime::windows {
struct ModePresentation {
  FocusLease lease;
  // Activation does not carry these values. Unknown is not an assumed default.
  std::optional<bool> chinese, chinese_punctuation, fullwidth;
};
// Single active-owner projection, independent of candidate/composition state.
class ModeMailbox final {
public:
  // Input queue only, under the active focus gate after mode synchronization.
  void event(const FocusLease &lease, const FanyImeNamedpipeData &packet) {
    std::lock_guard lock(mutex_);
    if (stopped_ || packet.client_id != lease.transport.client)
      return;
    if (!latest_ || !matches(latest_->lease, lease))
      latest_ = ModePresentation{lease, {}, {}, {}};
    switch (packet.event_type) {
    case FanyImePipeEventType::StatusSnapshot:
    case FanyImePipeEventType::FocusRestored:
      latest_->chinese = packet.keycode != 0;
      latest_->chinese_punctuation = packet.pinyin_length != 0;
      latest_->fullwidth = packet.modifiers_down != 0;
      break;
    case FanyImePipeEventType::IMESwitch:
      latest_->chinese = packet.keycode != 0;
      break;
    case FanyImePipeEventType::PuncSwitch:
      latest_->chinese_punctuation = packet.keycode != 0;
      break;
    case FanyImePipeEventType::DoubleSingleByteSwitch:
      latest_->fullwidth = packet.keycode != 0;
      break;
    }
  }
  std::optional<ModePresentation> snapshot(FocusGate &gate,
                                          MainTransport &transport) {
    std::optional<FocusLease> lease;
    {
      std::unique_lock lock(mutex_, std::try_to_lock);
      if (!lock || !latest_)
        return std::nullopt;
      lease = latest_->lease;
    }
    std::optional<ModePresentation> result;
    gate.try_with_active(*lease, [&] {
      std::unique_lock lock(mutex_, std::try_to_lock);
      if (!lock || !latest_ || !matches(latest_->lease, *lease))
        return;
      result = latest_;
      lock.unlock();
      if (!transport.try_current(lease->transport))
        result.reset();
    });
    return result;
  }
  void disconnected(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    if (latest_ && same_ticket(latest_->lease.transport, ticket))
      latest_.reset();
  }
  void stop() {
    std::lock_guard lock(mutex_);
    stopped_ = true;
    latest_.reset();
  }
private:
  static bool matches(const FocusLease &a, const FocusLease &b) {
    return a.epoch == b.epoch && a.token == b.token &&
           same_ticket(a.transport, b.transport);
  }
  std::mutex mutex_;
  bool stopped_ = false;
  std::optional<ModePresentation> latest_;
};
} // namespace msime::windows

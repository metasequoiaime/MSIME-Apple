#pragma once

namespace msime::windows {

// The TSF adapter must distinguish a confirmed write from an ambiguous write.
// Only DefinitelyNotSent may be handed to the local fallback path; replaying an
// ambiguous event can duplicate text in the target application.
enum class KeyEventSendResult {
  Sent,
  DefinitelyNotSent,
  DeliveryAmbiguous,
};

constexpr bool definitely_not_sent(KeyEventSendResult result) noexcept {
  return result == KeyEventSendResult::DefinitelyNotSent;
}

} // namespace msime::windows

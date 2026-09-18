#pragma once

namespace msime::windows {
// A terminal Aux fallback may only acknowledge a client that still has a
// live queue-owned session. Unknown/quiesced clients require a fresh explicit
// activation rather than an unauthenticated "OK".
constexpr bool terminal_deactivation_state_available(bool client_registered,
                                                     bool session_alive) noexcept {
  return client_registered && session_alive;
}
} // namespace msime::windows

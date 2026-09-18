#pragma once
#include <algorithm>
#include <cstdint>
#include <stdexcept>

namespace msime::windows {
// Supervision rules ported from the shipped watchdog. The decision is pure so
// the backoff can be exercised without starting processes; the supervisor only
// supplies what actually happened.
namespace watchdog {
// The Server reports why it stopped through its exit code. Anything else is an
// unclean exit: a crash, or the user ending the process.
inline constexpr uint32_t stop_exit_code = 0x4D530001u;
inline constexpr uint32_t restart_exit_code = 0x4D530002u;
inline constexpr uint32_t healthy_run_milliseconds = 30'000u;
inline constexpr uint32_t maximum_restart_delay_milliseconds = 30'000u;
// A requested restart comes back quickly; an unclean exit after a healthy run
// waits long enough for the previous process to release its shared state.
inline constexpr uint32_t requested_restart_delay_milliseconds = 250u;
inline constexpr uint32_t unclean_restart_delay_milliseconds = 2'000u;
inline constexpr uint32_t initial_restart_delay_milliseconds = 1'000u;
} // namespace watchdog

struct WatchdogDecision {
  bool keep_running;
  uint32_t delay_milliseconds;
  friend bool operator==(const WatchdogDecision &left,
                         const WatchdogDecision &right) {
    return left.keep_running == right.keep_running &&
           left.delay_milliseconds == right.delay_milliseconds;
  }
};

/// What to do after the supervised Server exited.
/// `previous_delay` is the delay that preceded this run, so repeated early
/// failures back off instead of spinning.
inline WatchdogDecision watchdog_after_exit(uint32_t exit_code,
                                            uint64_t run_milliseconds,
                                            uint32_t previous_delay) {
  if (previous_delay > watchdog::maximum_restart_delay_milliseconds)
    throw std::invalid_argument("Invalid watchdog delay");
  // A stop is the user's decision, not a failure: the watchdog leaves with it.
  if (exit_code == watchdog::stop_exit_code)
    return {false, 0};
  if (exit_code == watchdog::restart_exit_code)
    return {true, watchdog::requested_restart_delay_milliseconds};
  if (run_milliseconds >= watchdog::healthy_run_milliseconds)
    return {true, watchdog::unclean_restart_delay_milliseconds};
  // Failing immediately and repeatedly doubles the wait, never below the
  // unclean floor and never past the cap.
  const uint32_t doubled =
      previous_delay > watchdog::maximum_restart_delay_milliseconds / 2
          ? watchdog::maximum_restart_delay_milliseconds
          : previous_delay * 2;
  return {true, (std::min)((std::max)(doubled,
                                      watchdog::unclean_restart_delay_milliseconds),
                           watchdog::maximum_restart_delay_milliseconds)};
}

/// What to do when the Server could not be started at all.
inline WatchdogDecision watchdog_after_failed_start(uint32_t previous_delay) {
  if (previous_delay > watchdog::maximum_restart_delay_milliseconds)
    throw std::invalid_argument("Invalid watchdog delay");
  const uint32_t doubled =
      previous_delay > watchdog::maximum_restart_delay_milliseconds / 2
          ? watchdog::maximum_restart_delay_milliseconds
          : previous_delay * 2;
  return {true, (std::max)(doubled, watchdog::initial_restart_delay_milliseconds)};
}
} // namespace msime::windows

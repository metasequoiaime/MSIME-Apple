#include "WatchdogPolicy.h"
#include <stdexcept>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Watchdog policy validation failed");
}
int main() {
  using namespace msime::windows::watchdog;

  // A requested stop ends supervision; nothing restarts behind the user.
  require(watchdog_after_exit(stop_exit_code, 0, initial_restart_delay_milliseconds) ==
          (WatchdogDecision{false, 0}));
  require(watchdog_after_exit(stop_exit_code, healthy_run_milliseconds * 10,
                              maximum_restart_delay_milliseconds) ==
          (WatchdogDecision{false, 0}));

  // A requested restart comes back promptly whatever the previous backoff was.
  require(watchdog_after_exit(restart_exit_code, 5, maximum_restart_delay_milliseconds) ==
          (WatchdogDecision{true, requested_restart_delay_milliseconds}));

  // An unclean exit after a healthy run waits for the old process to release
  // its shared state, and does not inherit an earlier backoff.
  require(watchdog_after_exit(0, healthy_run_milliseconds, 8'000) ==
          (WatchdogDecision{true, unclean_restart_delay_milliseconds}));
  require(watchdog_after_exit(0xC0000005u, healthy_run_milliseconds + 1, 0) ==
          (WatchdogDecision{true, unclean_restart_delay_milliseconds}));

  // Failing immediately doubles the wait, never below the unclean floor.
  require(watchdog_after_exit(1, 10, 0).delay_milliseconds ==
          unclean_restart_delay_milliseconds);
  require(watchdog_after_exit(1, 10, initial_restart_delay_milliseconds).delay_milliseconds ==
          unclean_restart_delay_milliseconds);
  require(watchdog_after_exit(1, 10, 2'000).delay_milliseconds == 4'000);
  require(watchdog_after_exit(1, 10, 4'000).delay_milliseconds == 8'000);

  // The cap holds, including when doubling would overflow past it.
  require(watchdog_after_exit(1, 10, 16'000).delay_milliseconds ==
          maximum_restart_delay_milliseconds);
  require(watchdog_after_exit(1, 10, maximum_restart_delay_milliseconds).delay_milliseconds ==
          maximum_restart_delay_milliseconds);

  // A run one millisecond short of healthy is still an early failure.
  require(watchdog_after_exit(1, healthy_run_milliseconds - 1, 4'000).delay_milliseconds ==
          8'000);

  // A Server that cannot be started at all retries with its own backoff.
  require(watchdog_after_failed_start(0) ==
          (WatchdogDecision{true, initial_restart_delay_milliseconds}));
  require(watchdog_after_failed_start(initial_restart_delay_milliseconds).delay_milliseconds ==
          2'000);
  require(watchdog_after_failed_start(maximum_restart_delay_milliseconds).delay_milliseconds ==
          maximum_restart_delay_milliseconds);

  // A delay beyond the cap is not a state this supervisor can reach.
  bool caught = false;
  try {
    (void)watchdog_after_exit(1, 10, maximum_restart_delay_milliseconds + 1);
  } catch (const std::invalid_argument &) {
    caught = true;
  }
  require(caught);
  caught = false;
  try {
    (void)watchdog_after_failed_start(maximum_restart_delay_milliseconds + 1);
  } catch (const std::invalid_argument &) {
    caught = true;
  }
  require(caught);
}

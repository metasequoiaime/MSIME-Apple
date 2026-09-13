#include "TrayMenuDispatch.h"
#include <atomic>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Tray dispatch test failed at line " +
                             std::to_string(line));
}
} // namespace
#define require(...) require_at((__VA_ARGS__), __LINE__)

int main() {
  try {
    TrayMenuMailbox mailbox;
    require(!mailbox.take());

    // Only the latest request survives: a flood cannot queue up openings.
    mailbox.publish({10, 20});
    mailbox.publish({30, 40});
    require(mailbox.sequence() == 2);
    const auto latest = mailbox.take();
    require(latest && latest->center_x == 30 && latest->top == 40);
    require(!mailbox.take());

    // A listener shutting down must not reach a window being torn down.
    mailbox.stop();
    mailbox.publish({50, 60});
    require(!mailbox.take());

    // Concurrent publishing never yields a torn value and never queues.
    TrayMenuMailbox shared;
    std::atomic<bool> running{true};
    std::thread writer([&] {
      for (int index = 0; index < 5000 && running.load(); ++index)
        shared.publish({index, index + 1});
    });
    int observed = 0;
    while (writer.joinable() && observed < 200) {
      if (const auto value = shared.take()) {
        require(value->top == value->center_x + 1);
        ++observed;
      }
      if (shared.sequence() >= 5000)
        break;
    }
    running.store(false);
    writer.join();

    // A request with the menu closed opens it.
    require(tray_menu_request_action(false, 1000, 0) ==
            TrayMenuRequestAction::Show);
    // A repeat inside the debounce window is the same click arriving twice.
    require(tray_menu_request_action(true, 1000, 900) ==
            TrayMenuRequestAction::None);
    // A deliberate second click closes it again.
    require(tray_menu_request_action(true, 2000, 1000) ==
            TrayMenuRequestAction::Hide);

    // Dismissal. Nothing to dismiss when hidden.
    require(!tray_menu_dismissal(false, 5000, 0, 0, false, true, true));
    // The click that opened the menu is often still down on the first pump.
    require(!tray_menu_dismissal(true, 1050, 1000, 1000, false, true, false));
    // After the grace period an outside click closes it.
    require(tray_menu_dismissal(true, 1300, 1000, 1000, false, true, false));
    // A click inside the card is a selection, not a dismissal.
    require(!tray_menu_dismissal(true, 1300, 1000, 1000, true, true, false));
    // Another window taking the foreground closes it.
    require(tray_menu_dismissal(true, 1300, 1000, 1000, true, false, true));
    // Idle with the pointer away closes it, but not a moment early.
    require(!tray_menu_dismissal(true, 6299, 1000, 1300, false, false, false));
    require(tray_menu_dismissal(true, 6300, 1000, 1300, false, false, false));
    // Hovering keeps it open, up to an absolute cap.
    require(!tray_menu_dismissal(true, 20000, 1000, 1000, true, false, false));
    require(tray_menu_dismissal(true, 31000, 1000, 1000, true, false, false));

    std::cout << "Tray dispatch: latest-wins mailbox and open/close policy\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}

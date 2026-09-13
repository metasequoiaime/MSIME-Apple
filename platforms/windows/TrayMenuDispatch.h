#pragma once
#include "AuxMessage.h"
#include <cstdint>
#include <mutex>
#include <optional>

namespace msime::windows {
// The Aux listener runs on its own thread; the tray window belongs to the UI
// thread that created it. Only this value crosses between them, and only the
// latest request is kept: a flood of messages can never queue up work.
class TrayMenuMailbox final {
public:
  void publish(const TrayMenuAnchor &anchor) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_)
      return;
    pending_ = anchor;
    ++sequence_;
  }
  std::optional<TrayMenuAnchor> take() {
    std::lock_guard<std::mutex> lock(mutex_);
    auto pending = pending_;
    pending_.reset();
    return pending;
  }
  uint64_t sequence() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return sequence_;
  }
  // After stop() a late publish from a dying listener cannot reach a window
  // that is being torn down.
  void stop() {
    std::lock_guard<std::mutex> lock(mutex_);
    stopped_ = true;
    pending_.reset();
  }

private:
  mutable std::mutex mutex_;
  std::optional<TrayMenuAnchor> pending_;
  uint64_t sequence_ = 0;
  bool stopped_ = false;
};

enum class TrayMenuRequestAction { None, Show, Hide };

// Repeated clicks arrive as separate messages. Within this window a second
// request is the user double-clicking, not asking for the menu twice.
inline constexpr uint64_t tray_menu_debounce_milliseconds = 400;

inline TrayMenuRequestAction tray_menu_request_action(bool visible, uint64_t now,
                                                      uint64_t shown_at) {
  if (!visible)
    return TrayMenuRequestAction::Show;
  // Clicking the button again while the menu is open closes it, which is what
  // the language-bar button does elsewhere in Windows.
  if (now - shown_at < tray_menu_debounce_milliseconds)
    return TrayMenuRequestAction::None;
  return TrayMenuRequestAction::Hide;
}

// The card is WS_EX_NOACTIVATE, so it never receives WM_KILLFOCUS and cannot
// close itself the usual way. The UI pump therefore polls these inputs.
inline constexpr uint64_t tray_menu_open_grace_milliseconds = 150;
inline constexpr uint64_t tray_menu_idle_milliseconds = 5000;
inline constexpr uint64_t tray_menu_maximum_milliseconds = 30000;

inline bool tray_menu_dismissal(bool visible, uint64_t now, uint64_t shown_at,
                                uint64_t pointer_left_at, bool pointer_inside,
                                bool button_down, bool foreground_changed) {
  if (!visible)
    return false;
  // The click that opened the menu is often still down when the first pump
  // runs; dismissing on it would close the menu immediately.
  if (now - shown_at < tray_menu_open_grace_milliseconds)
    return false;
  if (foreground_changed)
    return true;
  if (button_down && !pointer_inside)
    return true;
  // Never leave the card on screen forever if the user walks away.
  if (now - shown_at >= tray_menu_maximum_milliseconds)
    return true;
  if (!pointer_inside && now - pointer_left_at >= tray_menu_idle_milliseconds)
    return true;
  return false;
}
} // namespace msime::windows

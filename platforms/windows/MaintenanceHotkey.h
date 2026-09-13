#pragma once

#include "MaintenanceHotkeys.h"

#include <windows.h>

#include <functional>

namespace msime::windows {
// Installs the global maintenance shortcuts on a low-level keyboard hook.
//
// A hook is what the reference uses and what these shortcuts require: they must
// work while another application has focus, which a TSF key sink cannot see.
// The stroke is consumed so the focused application never receives a stray
// digit or letter.
class MaintenanceHotkeyController final {
public:
  // Return true when the action was handled; only then is the stroke consumed.
  using Handler = std::function<bool(MaintenanceHotkey)>;

  explicit MaintenanceHotkeyController(Handler handler);
  ~MaintenanceHotkeyController();
  MaintenanceHotkeyController(const MaintenanceHotkeyController &) = delete;
  MaintenanceHotkeyController &operator=(const MaintenanceHotkeyController &) = delete;
  bool installed() const { return hook_ != nullptr; }

private:
  static LRESULT CALLBACK keyboard_proc(int code, WPARAM wparam, LPARAM lparam);
  Handler handler_;
  HHOOK hook_ = nullptr;
  static MaintenanceHotkeyController *instance_;
};
} // namespace msime::windows

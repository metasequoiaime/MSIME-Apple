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

  // Reports the new Caps Lock state on every press. The Server is the
  // authority for it; the TIP only sampled it at activation.
  using CapsSink = std::function<void(bool)>;
  explicit MaintenanceHotkeyController(Handler handler, CapsSink caps = {});
  ~MaintenanceHotkeyController();
  MaintenanceHotkeyController(const MaintenanceHotkeyController &) = delete;
  MaintenanceHotkeyController &operator=(const MaintenanceHotkeyController &) = delete;
  bool installed() const { return hook_ != nullptr; }

private:
  static LRESULT CALLBACK keyboard_proc(int code, WPARAM wparam, LPARAM lparam);
  Handler handler_;
  CapsSink caps_sink_;
  bool caps_ = false;
  HHOOK hook_ = nullptr;
  static MaintenanceHotkeyController *instance_;
};
} // namespace msime::windows

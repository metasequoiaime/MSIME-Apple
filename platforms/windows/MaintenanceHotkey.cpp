#include "MaintenanceHotkey.h"

namespace msime::windows {
MaintenanceHotkeyController *MaintenanceHotkeyController::instance_ = nullptr;

MaintenanceHotkeyController::MaintenanceHotkeyController(Handler handler)
    : handler_(std::move(handler)) {
  if (!handler_)
    return;
  instance_ = this;
  hook_ = SetWindowsHookExW(WH_KEYBOARD_LL,
                            &MaintenanceHotkeyController::keyboard_proc,
                            GetModuleHandleW(nullptr), 0);
  // A hook that cannot be installed leaves the shortcuts inert. It is not
  // worth failing the Server over: every other input path still works.
  if (!hook_ && instance_ == this)
    instance_ = nullptr;
}

MaintenanceHotkeyController::~MaintenanceHotkeyController() {
  if (hook_)
    UnhookWindowsHookEx(hook_);
  hook_ = nullptr;
  if (instance_ == this)
    instance_ = nullptr;
}

LRESULT CALLBACK MaintenanceHotkeyController::keyboard_proc(int code,
                                                           WPARAM wparam,
                                                           LPARAM lparam) {
  auto *self = instance_;
  if (code != HC_ACTION || !self || !self->handler_)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  if (wparam != WM_KEYDOWN && wparam != WM_SYSKEYDOWN)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  const auto *event = reinterpret_cast<const KBDLLHOOKSTRUCT *>(lparam);
  if (!event)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  // Do not act on strokes this process injected, or a handler that types
  // something could drive itself.
  if (event->flags & LLKHF_INJECTED)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  const bool ctrl = (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
  const bool shift = (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
  const bool alt = (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
  const auto hotkey = maintenance_hotkey(event->vkCode, ctrl, shift, alt);
  if (!hotkey)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  bool handled = false;
  try {
    handled = self->handler_(*hotkey);
  } catch (...) {
    handled = false;
  }
  // Consume only what was actually handled. Swallowing a stroke the Server
  // ignored would delete a keypress from the focused application for nothing.
  if (handled)
    return 1;
  return CallNextHookEx(nullptr, code, wparam, lparam);
}
} // namespace msime::windows

#include "VoiceHotkey.h"

#include <windows.h>

#include <utility>

namespace msime::windows {
namespace {
constexpr wchar_t kClassName[] = L"MSIMEClientVoiceHotkeyWindow";
constexpr UINT kStartMessage = WM_APP + 200;
constexpr UINT kToggleMessage = WM_APP + 201;
constexpr UINT kStopMessage = WM_APP + 202;
constexpr UINT kLockMessage = WM_APP + 203;
constexpr UINT kCancelMessage = WM_APP + 204;
}

VoiceHotkeyController *VoiceHotkeyController::instance_ = nullptr;

VoiceHotkeyController::VoiceHotkeyController(VoiceInputSession &voice,
                                             ConfigProvider config,
                                             ActiveProvider active)
    : voice_(voice), config_provider_(std::move(config)),
      active_provider_(std::move(active)) {
  if (instance_)
    return;
  WNDCLASSW klass{};
  klass.lpfnWndProc = &VoiceHotkeyController::window_proc;
  klass.hInstance = GetModuleHandleW(nullptr);
  klass.lpszClassName = kClassName;
  RegisterClassW(&klass);
  window_ = CreateWindowExW(0, kClassName, L"", 0, 0, 0, 0, 0,
                            HWND_MESSAGE, nullptr, klass.hInstance, this);
  if (window_) {
    instance_ = this;
    hook_ = SetWindowsHookExW(WH_KEYBOARD_LL,
                              &VoiceHotkeyController::keyboard_proc,
                              klass.hInstance, 0);
  }
}

VoiceHotkeyController::~VoiceHotkeyController() {
  if (hook_)
    UnhookWindowsHookEx(hook_);
  hook_ = nullptr;
  if (instance_ == this)
    instance_ = nullptr;
  if (window_)
    DestroyWindow(window_);
  window_ = nullptr;
  reset_state();
}

LRESULT CALLBACK VoiceHotkeyController::window_proc(HWND hwnd, UINT message,
                                                      WPARAM wparam,
                                                      LPARAM lparam) {
  auto *self = reinterpret_cast<VoiceHotkeyController *>(
      GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    const auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
    self = static_cast<VoiceHotkeyController *>(create->lpCreateParams);
    SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  return self ? self->handle_window(hwnd, message, wparam, lparam)
              : DefWindowProcW(hwnd, message, wparam, lparam);
}

LRESULT VoiceHotkeyController::handle_window(HWND hwnd, UINT message,
                                               WPARAM wparam, LPARAM lparam) {
  (void)wparam;
  (void)lparam;
  switch (message) {
  case kStartMessage:
    if (!voice_.recording())
      voice_.toggle();
    return 0;
  case kToggleMessage:
    voice_.toggle();
    return 0;
  case kStopMessage:
    voice_.stop();
    return 0;
  case kLockMessage:
    voice_.lock();
    return 0;
  case kCancelMessage:
    voice_.cancel();
    cancel_posted_ = false;
    return 0;
  default:
    return DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

bool VoiceHotkeyController::ctrl_pressed() const {
  return lctrl_pressed_.load() || rctrl_pressed_.load();
}
bool VoiceHotkeyController::win_pressed() const {
  return lwin_pressed_.load() || rwin_pressed_.load();
}
bool VoiceHotkeyController::hold_pressed(HoldShortcut shortcut) const {
  switch (shortcut) {
  case HoldShortcut::RAlt:
    return ralt_pressed_.load();
  case HoldShortcut::CtrlWin:
    return ctrl_pressed() && win_pressed();
  case HoldShortcut::RCtrlRAlt:
    return rctrl_pressed_.load() && ralt_pressed_.load();
  default:
    return false;
  }
}

void VoiceHotkeyController::activate(HoldShortcut shortcut) {
  active_hold_.store(shortcut);
  cancel_posted_.store(false);
  if (shortcut == HoldShortcut::RAlt || shortcut == HoldShortcut::RCtrlRAlt)
    suppress_ralt_until_up_.store(true);
  else if (shortcut == HoldShortcut::CtrlWin)
    suppress_win_until_up_.store(true);
  if (window_)
    PostMessageW(window_, voice_.locked() ? kStopMessage : kStartMessage, 0,
                 0);
}

void VoiceHotkeyController::reset_state() {
  ralt_pressed_ = false;
  lctrl_pressed_ = false;
  rctrl_pressed_ = false;
  lwin_pressed_ = false;
  rwin_pressed_ = false;
  f9_pressed_ = false;
  ctrl_f9_consumed_ = false;
  cancel_posted_ = false;
  suppress_ralt_until_up_ = false;
  suppress_win_until_up_ = false;
  active_hold_ = HoldShortcut::None;
}

LRESULT CALLBACK VoiceHotkeyController::keyboard_proc(int code, WPARAM wparam,
                                                        LPARAM lparam) {
  if (code != HC_ACTION || !instance_)
    return CallNextHookEx(nullptr, code, wparam, lparam);
  auto &self = *instance_;
  const auto *key = reinterpret_cast<KBDLLHOOKSTRUCT *>(lparam);
  if (!key)
    return CallNextHookEx(self.hook_, code, wparam, lparam);
  const bool down = wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN;
  const bool up = wparam == WM_KEYUP || wparam == WM_SYSKEYUP;
  const auto config = self.config_provider_();
  const auto active_before = self.active_hold_.load();

  if (key->vkCode == VK_LCONTROL || key->vkCode == VK_RCONTROL) {
    auto &state = key->vkCode == VK_LCONTROL ? self.lctrl_pressed_
                                             : self.rctrl_pressed_;
    state.store(down ? true : up ? false : state.load());
  } else if (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN) {
    auto &state = key->vkCode == VK_LWIN ? self.lwin_pressed_ : self.rwin_pressed_;
    state.store(down ? true : up ? false : state.load());
  } else if (key->vkCode == VK_RMENU) {
    self.ralt_pressed_.store(down ? true : up ? false : self.ralt_pressed_.load());
  }

  if (!config.enabled || !self.active_provider_()) {
    self.active_hold_ = HoldShortcut::None;
    if (self.voice_.recording() && !self.cancel_posted_.exchange(true))
      PostMessageW(self.window_, kCancelMessage, 0, 0);
    const bool suppress_ralt = key->vkCode == VK_RMENU &&
                               self.suppress_ralt_until_up_.load();
    const bool suppress_win = (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN) &&
                              self.suppress_win_until_up_.load();
    if (up && key->vkCode == VK_RMENU)
      self.suppress_ralt_until_up_ = false;
    if (up && (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN))
      self.suppress_win_until_up_ = false;
    return suppress_ralt || suppress_win
               ? 1
               : CallNextHookEx(self.hook_, code, wparam, lparam);
  }

  if (key->vkCode == VK_F9 && config.hotkey_ctrl_f9) {
    if (down && !self.f9_pressed_.exchange(true) && self.ctrl_pressed()) {
      self.ctrl_f9_consumed_ = true;
      PostMessageW(self.window_, kToggleMessage, 0, 0);
      return 1;
    }
    if (up) {
      self.f9_pressed_ = false;
      if (self.ctrl_f9_consumed_.exchange(false))
        return 1;
    }
  } else if (key->vkCode == VK_F9 && up) {
    self.f9_pressed_ = false;
    self.ctrl_f9_consumed_ = false;
  }

  if (active_before == HoldShortcut::None && down) {
    if (config.hotkey_rctrl_ralt && key->vkCode == VK_RMENU &&
        self.rctrl_pressed_.load())
      self.activate(HoldShortcut::RCtrlRAlt);
    else if (config.hotkey_ctrl_win &&
             (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN) &&
             self.ctrl_pressed())
      self.activate(HoldShortcut::CtrlWin);
    else if (config.hotkey_ralt && key->vkCode == VK_RMENU)
      self.activate(HoldShortcut::RAlt);
  } else if (active_before != HoldShortcut::None && up &&
             !self.hold_pressed(active_before)) {
    self.active_hold_ = HoldShortcut::None;
    if (!self.voice_.locked())
      PostMessageW(self.window_, kStopMessage, 0, 0);
  }

  const auto active_now = self.active_hold_.load();
  if (key->vkCode == VK_SPACE && active_now != HoldShortcut::None &&
      config.hotkey_hold_space_lock) {
    if (down && !self.voice_.locked())
      PostMessageW(self.window_, kLockMessage, 0, 0);
    return 1;
  }
  if (key->vkCode == VK_ESCAPE && self.voice_.recording()) {
    if (down)
      PostMessageW(self.window_, kCancelMessage, 0, 0);
    return 1;
  }

  const bool suppress_ralt = key->vkCode == VK_RMENU &&
                             self.suppress_ralt_until_up_.load();
  const bool suppress_win = (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN) &&
                            self.suppress_win_until_up_.load();
  if (up && key->vkCode == VK_RMENU)
    self.suppress_ralt_until_up_ = false;
  if (up && (key->vkCode == VK_LWIN || key->vkCode == VK_RWIN))
    self.suppress_win_until_up_ = false;
  return suppress_ralt || suppress_win
             ? 1
             : CallNextHookEx(self.hook_, code, wparam, lparam);
}
} // namespace msime::windows

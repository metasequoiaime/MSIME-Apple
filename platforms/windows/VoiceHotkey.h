#pragma once

#include "VoiceInputSession.h"

#include <windows.h>

#include <atomic>
#include <functional>

namespace msime::windows {
class VoiceHotkeyController final {
public:
  using ConfigProvider = std::function<VoiceInputConfig()>;
  using ActiveProvider = std::function<bool()>;

  VoiceHotkeyController(VoiceInputSession &voice, ConfigProvider config,
                        ActiveProvider active);
  ~VoiceHotkeyController();
  VoiceHotkeyController(const VoiceHotkeyController &) = delete;
  VoiceHotkeyController &operator=(const VoiceHotkeyController &) = delete;

private:
  enum class HoldShortcut { None, RAlt, CtrlWin, RCtrlRAlt };
  static LRESULT CALLBACK window_proc(HWND, UINT, WPARAM, LPARAM);
  static LRESULT CALLBACK keyboard_proc(int, WPARAM, LPARAM);
  LRESULT handle_window(HWND, UINT, WPARAM, LPARAM);
  void activate(HoldShortcut);
  void reset_state();
  bool ctrl_pressed() const;
  bool win_pressed() const;
  bool hold_pressed(HoldShortcut) const;

  VoiceInputSession &voice_;
  ConfigProvider config_provider_;
  ActiveProvider active_provider_;
  HWND window_ = nullptr;
  HHOOK hook_ = nullptr;
  std::atomic<bool> ralt_pressed_{false};
  std::atomic<bool> lctrl_pressed_{false};
  std::atomic<bool> rctrl_pressed_{false};
  std::atomic<bool> lwin_pressed_{false};
  std::atomic<bool> rwin_pressed_{false};
  std::atomic<bool> f9_pressed_{false};
  std::atomic<bool> ctrl_f9_consumed_{false};
  std::atomic<bool> cancel_posted_{false};
  std::atomic<bool> suppress_ralt_until_up_{false};
  std::atomic<bool> suppress_win_until_up_{false};
  std::atomic<HoldShortcut> active_hold_{HoldShortcut::None};
  static VoiceHotkeyController *instance_;
};
} // namespace msime::windows

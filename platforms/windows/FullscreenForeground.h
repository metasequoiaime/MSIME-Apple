#pragma once
#include <initializer_list>
#include <windows.h>

namespace msime::windows {
// Is the foreground window a full-screen application?
//
// The toolbar sits topmost, so without this it floats over full-screen video
// and presentations. Mirrors the reference CheckFullscreen: compare the
// window's rectangle against its monitor and exclude the shell, whose desktop
// and tray windows legitimately cover the screen.
inline bool foreground_is_fullscreen(HWND foreground) {
  if (!foreground || !IsWindowVisible(foreground))
    return false;
  // The desktop and the shell tray are always "full screen" and must not count.
  if (foreground == GetShellWindow() || foreground == GetDesktopWindow())
    return false;
  wchar_t klass[64]{};
  if (GetClassNameW(foreground, klass, 64)) {
    for (const wchar_t *shell : {L"Progman", L"WorkerW", L"Shell_TrayWnd"})
      if (!lstrcmpiW(klass, shell))
        return false;
  }
  RECT window{};
  if (!GetWindowRect(foreground, &window))
    return false;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(MonitorFromWindow(foreground, MONITOR_DEFAULTTONEAREST),
                       &monitor))
    return false;
  // Compare against the full monitor rather than the work area: a maximised
  // window covers the work area and must not be mistaken for full screen.
  const RECT &screen = monitor.rcMonitor;
  return window.left <= screen.left && window.top <= screen.top &&
         window.right >= screen.right && window.bottom >= screen.bottom;
}
} // namespace msime::windows

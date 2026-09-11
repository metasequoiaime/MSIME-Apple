#include "FloatingToolbarWindow.h"
#include <stdexcept>
#include <windowsx.h>

namespace msime::windows {
namespace {
constexpr wchar_t kClassName[] = L"MSIME.Client.Preview.FloatingToolbar";
constexpr int kWidth = 300;
constexpr int kHeight = 52;
bool same(const FocusLease &a, const FocusLease &b) {
  return a.epoch == b.epoch && a.token == b.token &&
         same_ticket(a.transport, b.transport);
}
} // namespace

FloatingToolbarWindow::FloatingToolbarWindow(Reader reader)
    : reader_(std::move(reader)) {
  if (!reader_) throw std::invalid_argument("Missing toolbar callback");
  WNDCLASSEXW type{};
  type.cbSize = sizeof(type);
  type.lpfnWndProc = procedure;
  type.hInstance = GetModuleHandleW(nullptr);
  type.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
  type.hbrBackground = GetSysColorBrush(COLOR_BTNFACE);
  type.lpszClassName = kClassName;
  if (!RegisterClassExW(&type) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    throw std::runtime_error("Toolbar class unavailable");
  window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                            kClassName, L"MSIME toolbar", WS_POPUP, 0, 0,
                            kWidth, kHeight, nullptr, nullptr, type.hInstance,
                            this);
  if (!window_) throw std::runtime_error("Toolbar window unavailable");
}
FloatingToolbarWindow::~FloatingToolbarWindow() { hide(); if (window_) DestroyWindow(window_); }
void FloatingToolbarWindow::hide() { shown_.reset(); if (window_) ShowWindow(window_, SW_HIDE); }
void FloatingToolbarWindow::refresh(bool enabled) {
  if (failed_) return;
  try {
    if (!enabled) { hide(); return; }
    const auto value = reader_();
    if (!value) { hide(); return; }
    const bool changed = !shown_ || !same(shown_->lease, value->lease) ||
                         shown_->chinese != value->chinese ||
                         shown_->chinese_punctuation != value->chinese_punctuation ||
                         shown_->fullwidth != value->fullwidth;
    if (!changed && IsWindowVisible(window_)) return;
    shown_ = value;
    RECT work{};
    const HMONITOR monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) throw std::runtime_error("Toolbar monitor unavailable");
    work = info.rcWork;
    if (!SetWindowPos(window_, HWND_TOPMOST, work.right - kWidth - 20,
                      work.bottom - kHeight - 20, kWidth, kHeight,
                      SWP_NOACTIVATE | SWP_SHOWWINDOW))
      throw std::runtime_error("Toolbar positioning failed");
    InvalidateRect(window_, nullptr, FALSE);
  } catch (...) { failed_ = true; hide(); }
}
void FloatingToolbarWindow::paint() {
  PAINTSTRUCT state{}; const HDC dc = BeginPaint(window_, &state);
  if (!dc) return;
  FillRect(dc, &state.rcPaint, GetSysColorBrush(COLOR_BTNFACE));
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, GetSysColor(COLOR_BTNTEXT));
  const auto value = reader_();
  if (value && shown_ && same(value->lease, shown_->lease)) {
    const wchar_t *labels[] = {value->chinese && *value->chinese ? L"中" : L"英",
                               value->chinese_punctuation && *value->chinese_punctuation ? L"。" : L".",
                               value->fullwidth && *value->fullwidth ? L"全" : L"半", L"设"};
    for (int i = 0; i < 4; ++i) { RECT cell{8 + i * 72, 8, 72 + i * 72, 44};
      DrawTextW(dc, labels[i], -1, &cell, DT_CENTER | DT_VCENTER | DT_SINGLELINE); }
  }
  EndPaint(window_, &state);
}
LRESULT CALLBACK FloatingToolbarWindow::procedure(HWND window, UINT message,
                                                    WPARAM w, LPARAM l) noexcept {
  auto *self = reinterpret_cast<FloatingToolbarWindow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) { self = static_cast<FloatingToolbarWindow *>(reinterpret_cast<CREATESTRUCTW *>(l)->lpCreateParams);
    self->window_ = window; SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self)); }
  if (!self) return DefWindowProcW(window, message, w, l);
  try { switch (message) {
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_ERASEBKGND: return 1;
    case WM_PAINT: self->paint(); return 0;
    case WM_LBUTTONDOWN:
      ReleaseCapture();
      SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return 0;
    case WM_NCLBUTTONDOWN:
      if (w == HTCLIENT || w == HTCAPTION) {
        ReleaseCapture();
        SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        return 0;
      }
      break;
  }} catch (...) { self->failed_ = true; self->hide(); return 0; }
  return DefWindowProcW(window, message, w, l);
}
} // namespace msime::windows

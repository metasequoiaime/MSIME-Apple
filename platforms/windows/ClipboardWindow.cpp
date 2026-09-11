#include "ClipboardWindow.h"
#ifdef _WIN32
#include <algorithm>
#include <windowsx.h>

namespace msime::windows {
namespace {
int scale(unsigned dpi, int value) { return (value * static_cast<int>(dpi) + 48) / 96; }
std::wstring utf16(const std::string &text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring result(static_cast<size_t>(size), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size) != size) return {};
  return result;
}
}
ClipboardWindow::ClipboardWindow(Reader reader, Click click, Remove remove, Clear clear) : reader_(std::move(reader)), click_(std::move(click)), remove_(std::move(remove)), clear_(std::move(clear)) {
  WNDCLASSW klass{}; klass.hInstance = GetModuleHandleW(nullptr); klass.lpfnWndProc = procedure; klass.lpszClassName = L"MSIMEClientClipboardWindow";
  RegisterClassW(&klass);
  window_ = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, klass.lpszClassName, L"Clipboard", WS_POPUP | WS_BORDER, 0, 0, 420, 320, nullptr, nullptr, klass.hInstance, this);
  if (!window_) failed_ = true;
}
ClipboardWindow::~ClipboardWindow() { if (window_) DestroyWindow(window_); }
void ClipboardWindow::hide() { if (window_) ShowWindow(window_, SW_HIDE); shown_.reset(); }
void ClipboardWindow::refresh() {
  if (!window_ || !reader_) return;
  try { shown_ = reader_(); if (!shown_ || !shown_->enabled || shown_->items.empty()) { hide(); return; } const unsigned next_dpi = std::max(96u, GetDpiForWindow(window_)); if (next_dpi != dpi_) { dpi_ = next_dpi; SetWindowPos(window_, nullptr, 0, 0, scale(dpi_, 420), scale(dpi_, 320), SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE); } POINT cursor{}; if (GetCursorPos(&cursor)) { const HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST); MONITORINFO info{}; info.cbSize = sizeof(info); if (GetMonitorInfoW(monitor, &info)) { RECT window{}; GetWindowRect(window_, &window); const int width = window.right - window.left; const int height = window.bottom - window.top; const int margin = scale(dpi_, 8); SetWindowPos(window_, HWND_TOP, info.rcWork.right - width - margin, info.rcWork.bottom - height - margin, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW); } } ShowWindow(window_, SW_SHOWNOACTIVATE); InvalidateRect(window_, nullptr, FALSE); } catch (...) { failed_ = true; hide(); }
}
void ClipboardWindow::paint() {
  PAINTSTRUCT ps{}; const auto dc = BeginPaint(window_, &ps); RECT client{}; GetClientRect(window_, &client);
  FillRect(dc, &client, static_cast<HBRUSH>(GetSysColorBrush(COLOR_WINDOW)));
  if (shown_) { const int top = scale(dpi_, 32); const int row_height = scale(dpi_, 26); HFONT font = CreateFontW(-scale(dpi_, 14), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, FF_DONTCARE, L"Segoe UI"); HGDIOBJ previous = font ? SelectObject(dc, font) : nullptr; SetBkMode(dc, TRANSPARENT); SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT)); RECT clear{scale(dpi_, 8), scale(dpi_, 4), client.right - scale(dpi_, 8), top - scale(dpi_, 6)}; SetTextColor(dc, GetSysColor(COLOR_BTNTEXT)); DrawTextW(dc, L"清空剪贴板历史", -1, &clear, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX); SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT)); int y = top; for (size_t i = 0; i < shown_->items.size() && y < client.bottom; ++i) { const auto text = utf16(shown_->items[i]); RECT row{scale(dpi_, 8), y, client.right - scale(dpi_, 8), y + scale(dpi_, 24)}; if (!text.empty()) DrawTextW(dc, text.c_str(), -1, &row, DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX); y += row_height; } if (previous) SelectObject(dc, previous); if (font) DeleteObject(font); }
  EndPaint(window_, &ps);
}
LRESULT CALLBACK ClipboardWindow::procedure(HWND window, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  auto *self = reinterpret_cast<ClipboardWindow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) { auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam); self = static_cast<ClipboardWindow *>(create->lpCreateParams); SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self)); }
  if (!self) return DefWindowProcW(window, message, wparam, lparam);
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT) { self->paint(); return 0; }
  if (message == WM_DPICHANGED) { self->dpi_ = std::max(96u, static_cast<unsigned>(HIWORD(wparam))); const auto *suggested = reinterpret_cast<const RECT *>(lparam); SetWindowPos(window, nullptr, suggested->left, suggested->top, suggested->right - suggested->left, suggested->bottom - suggested->top, SWP_NOZORDER | SWP_NOACTIVATE); InvalidateRect(window, nullptr, TRUE); return 0; }
  if (message == WM_LBUTTONUP && self->shown_) { const int y = GET_Y_LPARAM(lparam); const int top = scale(self->dpi_, 32); const int row = scale(self->dpi_, 26); if (y < top) { if (self->clear_) self->clear_(); return 0; } const size_t index = static_cast<size_t>((y - top) / row); if (y >= top && index < self->shown_->items.size() && self->click_) self->click_(index); return 0; }
  if (message == WM_RBUTTONUP && self->shown_) { const int y = GET_Y_LPARAM(lparam); const int top = scale(self->dpi_, 32); const int row = scale(self->dpi_, 26); if (y < top) return 0; const size_t index = static_cast<size_t>((y - top) / row); if (index < self->shown_->items.size() && self->remove_) self->remove_(index); return 0; }
  if (message == WM_KEYDOWN && wparam == VK_DELETE && (GetKeyState(VK_CONTROL) & 0x8000) && self->clear_) { self->clear_(); return 0; }
  if (message == WM_SETCURSOR && self->shown_) { POINT point{}; GetCursorPos(&point); ScreenToClient(window, &point); const int top = scale(self->dpi_, 32); if (point.y >= 0 && point.y < top + scale(self->dpi_, 26) * static_cast<int>(self->shown_->items.size())) { SetCursor(LoadCursorW(nullptr, MAKEINTRESOURCEW(32649))); return TRUE; } }
  if (message == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
  return DefWindowProcW(window, message, wparam, lparam);
}
} // namespace msime::windows
#endif

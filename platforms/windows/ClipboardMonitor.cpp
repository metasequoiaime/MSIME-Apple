#include "ClipboardHistory.h"
#ifdef _WIN32
#include <windows.h>
#include <string>

namespace msime::windows {
namespace {
std::string wide_to_utf8(const std::wstring &text) {
  if (text.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  if (size <= 0) return {};
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size, nullptr, nullptr);
  return result;
}
}
ClipboardMonitor::ClipboardMonitor(ClipboardHistory &history, Callback callback) : history_(history), callback_(std::move(callback)) {}
ClipboardMonitor::~ClipboardMonitor() { stop(); }
LRESULT CALLBACK ClipboardMonitor::window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto *monitor = reinterpret_cast<ClipboardMonitor *>(GetWindowLongPtrW(static_cast<HWND>(window), GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    auto *create = reinterpret_cast<CREATESTRUCTW *>(lparam);
    monitor = static_cast<ClipboardMonitor *>(create->lpCreateParams);
    SetWindowLongPtrW(static_cast<HWND>(window), GWLP_USERDATA, reinterpret_cast<LONG_PTR>(monitor));
  }
  if (monitor && message == WM_CLIPBOARDUPDATE && monitor->history_.enabled() && GetClipboardSequenceNumber() != monitor->sequence_) {
    monitor->sequence_ = GetClipboardSequenceNumber();
    if (IsClipboardFormatAvailable(CF_UNICODETEXT) && OpenClipboard(static_cast<HWND>(window))) {
      auto data = GetClipboardData(CF_UNICODETEXT);
      const auto *text = data ? static_cast<const wchar_t *>(GlobalLock(data)) : nullptr;
      const std::wstring value = text ? text : L"";
      if (text) GlobalUnlock(data);
      CloseClipboard();
      if (auto utf8 = wide_to_utf8(value); !utf8.empty() && monitor->history_.add(utf8) && monitor->callback_) monitor->callback_(std::move(utf8));
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
bool ClipboardMonitor::start() {
  if (window_) return true;
  const auto instance = GetModuleHandleW(nullptr);
  const wchar_t name[] = L"MSIMEClientClipboardMonitor";
  WNDCLASSW klass{}; klass.hInstance = instance; klass.lpfnWndProc = window_proc; klass.lpszClassName = name;
  RegisterClassW(&klass);
  window_ = CreateWindowExW(0, name, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, this);
  if (!window_) return false;
  sequence_ = GetClipboardSequenceNumber();
  return AddClipboardFormatListener(static_cast<HWND>(window_)) != FALSE;
}
void ClipboardMonitor::stop() {
  if (!window_) return;
  RemoveClipboardFormatListener(static_cast<HWND>(window_));
  DestroyWindow(static_cast<HWND>(window_)); window_ = nullptr;
}
} // namespace msime::windows
#endif

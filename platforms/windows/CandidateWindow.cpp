#include "CandidateWindow.h"
#include <algorithm>

namespace msime::windows {
namespace {
constexpr wchar_t class_name[] = L"MSIME.Client.Preview.Candidates";
constexpr int row_height = 28;
std::wstring wide(const std::string &text) {
  if (text.size() > 4096)
    throw std::invalid_argument("Oversized window text");
  if (text.empty())
    return {};
  const int count =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), nullptr, 0);
  if (!count)
    throw std::invalid_argument("Invalid window text");
  std::wstring result(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), result.data(),
                          count) != count)
    throw std::invalid_argument("Invalid window text");
  return result;
}
struct Painting {
  HWND window;
  PAINTSTRUCT state{};
  HDC dc;
  explicit Painting(HWND value)
      : window(value), dc(BeginPaint(window, &state)) {}
  ~Painting() { EndPaint(window, &state); }
};
} // namespace
CandidateWindow::CandidateWindow(Reader reader) : reader_(std::move(reader)) {
  if (!reader_)
    throw std::invalid_argument("Missing candidate reader");
  WNDCLASSEXW descriptor{};
  descriptor.cbSize = sizeof(descriptor);
  descriptor.lpfnWndProc = procedure;
  descriptor.hInstance = GetModuleHandleW(nullptr);
  descriptor.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
  descriptor.lpszClassName = class_name;
  // This process owns the class; no per-window unregister/re-register race.
  if (!RegisterClassExW(&descriptor) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    throw std::runtime_error("Candidate class unavailable");
  window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                            class_name, L"", WS_POPUP | WS_BORDER, 0, 0, 1, 1,
                            nullptr, nullptr, descriptor.hInstance, this);
  if (!window_)
    throw std::runtime_error("Candidate window unavailable");
}
CandidateWindow::~CandidateWindow() {
  if (window_)
    DestroyWindow(window_);
}
void CandidateWindow::hide() {
  shown_.reset();
  ShowWindow(window_, SW_HIDE);
}
void CandidateWindow::refresh() {
  if (failed_) {
    hide();
    return;
  }
  const auto value = reader_();
  if (!value || !value->visible) {
    hide();
    return;
  }
  if (value->candidates.size() > 9)
    throw std::invalid_argument("Oversized window page");
  if (shown_ && shown_->session == value->session &&
      shown_->generation == value->generation && shown_->x == value->x &&
      shown_->y == value->y && shown_->lease.epoch == value->lease.epoch &&
      shown_->lease.token == value->lease.token &&
      same_ticket(shown_->lease.transport, value->lease.transport))
    return; // Do not create a self-sustaining WM_PAINT polling loop.
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(
          MonitorFromPoint({value->x, value->y}, MONITOR_DEFAULTTONEAREST),
          &monitor))
    throw std::runtime_error("Candidate monitor unavailable");
  const auto &work = monitor.rcWork;
  const int width = static_cast<int>((std::min)(420L, work.right - work.left));
  const int height = static_cast<int>(
      (std::min)(static_cast<LONG>((value->candidates.size() + 1) * row_height +
                                   8),
                 work.bottom - work.top));
  if (width <= 0 || height <= 0)
    throw std::runtime_error("Invalid monitor bounds");
  const int x = (std::clamp)(value->x, static_cast<int>(work.left),
                             static_cast<int>(work.right) - width);
  const int y = (std::clamp)(value->y, static_cast<int>(work.top),
                             static_cast<int>(work.bottom) - height);
  if (!SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
                    SWP_NOACTIVATE | SWP_SHOWWINDOW))
    throw std::runtime_error("Candidate positioning failed");
  shown_ = value;
  InvalidateRect(window_, nullptr, FALSE);
}
void CandidateWindow::paint() {
  Painting painting(window_);
  if (!painting.dc)
    throw std::runtime_error("Candidate painting unavailable");
  RECT bounds{};
  GetClientRect(window_, &bounds);
  FillRect(painting.dc, &bounds, GetSysColorBrush(COLOR_WINDOW));
  const auto value = reader_(); // Never paint the last cached owner's text.
  if (!value || !value->visible) {
    hide();
    return;
  }
  if (value->candidates.size() > 9)
    throw std::invalid_argument("Oversized window page");
  const auto previous =
      SelectObject(painting.dc, GetStockObject(DEFAULT_GUI_FONT));
  SetBkMode(painting.dc, TRANSPARENT);
  auto line = [&](const std::wstring &text, size_t row, bool highlighted) {
    RECT rect{4, static_cast<LONG>(4 + row * row_height), bounds.right - 4,
              static_cast<LONG>(4 + (row + 1) * row_height)};
    if (highlighted)
      FillRect(painting.dc, &rect, GetSysColorBrush(COLOR_HIGHLIGHT));
    SetTextColor(painting.dc, GetSysColor(highlighted ? COLOR_HIGHLIGHTTEXT
                                                      : COLOR_WINDOWTEXT));
    rect.left += 4;
    DrawTextW(painting.dc, text.c_str(), static_cast<int>(text.size()), &rect,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  };
  line(wide(value->preedit), 0, false);
  for (size_t i = 0; i < value->candidates.size(); ++i)
    line(std::to_wstring(i + 1) + L". " + wide(value->candidates[i].text),
         i + 1, value->candidates[i].highlighted);
  SelectObject(painting.dc, previous);
}
LRESULT CALLBACK CandidateWindow::procedure(HWND window, UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam) noexcept {
  auto *self = reinterpret_cast<CandidateWindow *>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<CandidateWindow *>(
        reinterpret_cast<CREATESTRUCTW *>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->window_ = window;
  }
  if (self) {
    try {
      switch (message) {
      case WM_MOUSEACTIVATE:
        return MA_NOACTIVATEANDEAT;
      case WM_ERASEBKGND:
        return 1;
      case WM_DISPLAYCHANGE:
      case WM_SETTINGCHANGE:
        self->shown_.reset();
        return 0;
      case WM_PAINT:
        self->paint();
        return 0;
      case WM_CLOSE:
        self->hide();
        return 0;
      case WM_NCDESTROY:
        self->window_ = nullptr;
        SetWindowLongPtrW(window, GWLP_USERDATA, 0);
        break;
      }
    } catch (...) {
      self->failed_ = true;
      self->hide(); // No exception/input text may cross the Win32 callback.
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
} // namespace msime::windows

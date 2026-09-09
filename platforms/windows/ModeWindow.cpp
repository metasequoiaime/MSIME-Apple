#include "ModeWindow.h"
#include <windowsx.h>

namespace msime::windows {
namespace {
constexpr wchar_t class_name[] = L"MSIME.Client.Preview.Modes";
constexpr WorkerMode commands[] = {WorkerMode::Chinese,
                                   WorkerMode::English,
                                   WorkerMode::ChinesePunctuation,
                                   WorkerMode::AsciiPunctuation,
                                   WorkerMode::Fullwidth,
                                   WorkerMode::Halfwidth};
constexpr const wchar_t *labels[] = {L"中文",     L"English", L"中文标点",
                                     L"英文标点", L"全角",    L"半角"};
bool same(const FocusLease &a, const FocusLease &b) {
  return a.epoch == b.epoch && a.token == b.token &&
         same_ticket(a.transport, b.transport);
}
struct DpiScope {
  DPI_AWARENESS_CONTEXT previous =
      SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  DpiScope() {
    if (!previous)
      throw std::runtime_error("Mode DPI unavailable");
  }
  ~DpiScope() { SetThreadDpiAwarenessContext(previous); }
};
int cell_width(unsigned dpi) { return MulDiv(112, static_cast<int>(dpi), 96); }
int cell_height(unsigned dpi) { return MulDiv(34, static_cast<int>(dpi), 96); }
} // namespace
ModeWindow::ModeWindow(Reader reader, Click click)
    : reader_(std::move(reader)), click_(std::move(click)) {
  if (!reader_ || !click_)
    throw std::invalid_argument("Missing mode callback");
  DpiScope scope;
  WNDCLASSEXW type{};
  type.cbSize = sizeof(type);
  type.lpfnWndProc = procedure;
  type.hInstance = GetModuleHandleW(nullptr);
  type.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
  type.lpszClassName = class_name;
  if (!RegisterClassExW(&type) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    throw std::runtime_error("Mode class unavailable");
  window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
                            class_name, L"MSIME modes", WS_POPUP, 0, 0, 1, 1,
                            nullptr, nullptr, type.hInstance, this);
  if (!window_)
    throw std::runtime_error("Mode window unavailable");
}
ModeWindow::~ModeWindow() {
  if (window_)
    DestroyWindow(window_);
}
void ModeWindow::hide() {
  shown_.reset();
  painted_.reset();
  pressed_.reset();
  ShowWindow(window_, SW_HIDE);
}
void ModeWindow::refresh() {
  if (failed_)
    return;
  try {
    DpiScope scope;
    const auto value = reader_();
    if (!value) {
      hide();
      return;
    }
    const auto dpi = GetDpiForWindow(window_);
    if (!dpi)
      throw std::runtime_error("Mode DPI unavailable");
    const bool changed =
        !shown_ || !same(shown_->lease, value->lease) ||
        shown_->chinese != value->chinese ||
        shown_->chinese_punctuation != value->chinese_punctuation ||
        shown_->fullwidth != value->fullwidth || dpi_ != dpi;
    if (!changed)
      return;
    pressed_.reset();
    painted_.reset();
    shown_ = value;
    dpi_ = dpi;
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTOPRIMARY),
                         &monitor))
      throw std::runtime_error("Mode monitor unavailable");
    const int width = cell_width(dpi) * 2, height = cell_height(dpi) * 3;
    if (!SetWindowPos(window_, HWND_TOPMOST, monitor.rcWork.right - width,
                      monitor.rcWork.bottom - height, width, height,
                      SWP_NOACTIVATE | SWP_SHOWWINDOW))
      throw std::runtime_error("Mode positioning failed");
    InvalidateRect(window_, nullptr, FALSE);
  } catch (...) {
    failed_ = true;
    hide();
  }
}
void ModeWindow::paint() {
  PAINTSTRUCT state{};
  const auto dc = BeginPaint(window_, &state);
  struct End {
    HWND window;
    PAINTSTRUCT &state;
    ~End() { EndPaint(window, &state); }
  } end{window_, state};
  if (!dc)
    throw std::runtime_error("Mode paint unavailable");
  const auto value = reader_();
  if (!value || !shown_ || !same(value->lease, shown_->lease)) {
    hide();
    return;
  }
  const auto font = CreateFontW(
      -MulDiv(14, static_cast<int>(dpi_), 96), 0, 0, 0, FW_NORMAL, FALSE, FALSE,
      FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
  if (!font)
    throw std::runtime_error("Mode font unavailable");
  const auto old = SelectObject(dc, font);
  struct FontEnd {
    HDC dc;
    HGDIOBJ old;
    HFONT font;
    ~FontEnd() {
      if (old && old != HGDI_ERROR)
        SelectObject(dc, old);
      DeleteObject(font);
    }
  } font_end{dc, old, font};
  if (!old || old == HGDI_ERROR)
    throw std::runtime_error("Mode font failed");
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, GetSysColor(COLOR_BTNTEXT));
  const std::optional<bool> values[] = {
      value->chinese, value->chinese_punctuation, value->fullwidth};
  for (int i = 0; i < 6; ++i) {
    RECT rect{(i % 2) * cell_width(dpi_), (i / 2) * cell_height(dpi_),
              (i % 2 + 1) * cell_width(dpi_), (i / 2 + 1) * cell_height(dpi_)};
    FillRect(dc, &rect, GetSysColorBrush(COLOR_BTNFACE));
    DrawEdge(dc, &rect, EDGE_RAISED, BF_RECT);
    const auto current = values[i / 2];
    std::wstring text = labels[i];
    text += !current ? L" ?" : (*current == (i % 2 == 0) ? L" ✓" : L"");
    DrawTextW(dc, text.c_str(), -1, &rect,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  }
  painted_ = value;
}
std::optional<ModeClick> ModeWindow::hit(int x, int y) {
  if (!painted_ || !dpi_ || x < 0 || y < 0 || x >= 2 * cell_width(dpi_) ||
      y >= 3 * cell_height(dpi_))
    return {};
  const auto value = reader_();
  if (!value || !same(value->lease, painted_->lease))
    return {};
  return ModeClick{value->lease,
                   commands[y / cell_height(dpi_) * 2 + x / cell_width(dpi_)]};
}
LRESULT CALLBACK ModeWindow::procedure(HWND window, UINT message, WPARAM w,
                                       LPARAM l) noexcept {
  auto *self =
      reinterpret_cast<ModeWindow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<ModeWindow *>(
        reinterpret_cast<CREATESTRUCTW *>(l)->lpCreateParams);
    self->window_ = window;
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  }
  if (!self)
    return DefWindowProcW(window, message, w, l);
  try {
    switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
    case WM_ERASEBKGND:
      return 1;
    case WM_PAINT:
      self->paint();
      return 0;
    case WM_LBUTTONDOWN:
      self->pressed_ = self->hit(GET_X_LPARAM(l), GET_Y_LPARAM(l));
      return 0;
    case WM_LBUTTONUP: {
      const auto down = self->pressed_;
      self->pressed_.reset();
      const auto up = self->hit(GET_X_LPARAM(l), GET_Y_LPARAM(l));
      if (down && up && down->mode == up->mode && same(down->lease, up->lease))
        self->click_(*up);
      return 0;
    }
    case WM_CANCELMODE:
    case WM_CAPTURECHANGED:
      self->pressed_.reset();
      return 0;
    case WM_DPICHANGED:
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      self->shown_.reset();
      self->painted_.reset();
      self->pressed_.reset();
      return 0;
    }
  } catch (...) {
    self->failed_ = true;
    self->hide();
    return 0;
  }
  return DefWindowProcW(window, message, w, l);
}
} // namespace msime::windows

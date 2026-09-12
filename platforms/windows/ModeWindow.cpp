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
  layout_.reset();
  monitor_ = nullptr;
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
    // The mode panel follows the focused host, not an unrelated pointer move.
    const HWND foreground = GetForegroundWindow();
    const HMONITOR target =
        MonitorFromWindow(foreground ? foreground : window_,
                          MONITOR_DEFAULTTOPRIMARY);
    const bool changed =
        !shown_ || !same(shown_->lease, value->lease) ||
        shown_->chinese != value->chinese ||
        shown_->chinese_punctuation != value->chinese_punctuation ||
        shown_->fullwidth != value->fullwidth || dpi_ != dpi || monitor_ != target;
    if (!changed)
      return;
    pressed_.reset();
    painted_.reset();
    shown_ = value;
    dpi_ = dpi;
    MONITORINFO monitor{};
    monitor.cbSize = sizeof(monitor);
    if (!GetMonitorInfoW(target, &monitor))
      throw std::runtime_error("Mode monitor unavailable");
    layout_ = mode_layout(monitor.rcWork.left, monitor.rcWork.top,
                          monitor.rcWork.right, monitor.rcWork.bottom, dpi);
    if (!layout_) {
      hide();
      return;
    }
    if (!SetWindowPos(window_, HWND_TOPMOST, layout_->x, layout_->y,
                      layout_->width(), layout_->height(),
                      SWP_NOACTIVATE | SWP_SHOWWINDOW))
      throw std::runtime_error("Mode positioning failed");
    monitor_ = target;
    InvalidateRect(window_, nullptr, FALSE);
  } catch (...) {
    failed_ = true;
    hide();
  }
}
ModeWindow::Apartment::Apartment() {
  const HRESULT entered =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(entered) && entered != RPC_E_CHANGED_MODE)
    throw std::runtime_error("Mode apartment unavailable");
  owned = entered != RPC_E_CHANGED_MODE;
}
ModeWindow::Apartment::~Apartment() {
  if (owned)
    CoUninitialize();
}
void ModeWindow::set_palette(CandidatePalette palette) {
  palette_ = std::move(palette);
  painted_.reset();
  if (window_)
    InvalidateRect(window_, nullptr, FALSE);
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
  if (!value || !shown_ || !layout_ || !same(value->lease, shown_->lease)) {
    hide();
    return;
  }
  if (!device_.EnsureForWindow(window_))
    throw std::runtime_error("Mode device unavailable");
  auto *target = device_.GetRenderTarget();
  if (!target)
    throw std::runtime_error("Mode render target unavailable");
  auto brush = [&](const CandidateColor &color) {
    auto *value = device_.GetSolidColorBrush(
        D2D1::ColorF(color.r, color.g, color.b, color.a));
    if (!value)
      throw std::runtime_error("Mode brush unavailable");
    return value;
  };
  // The panel is sized in physical pixels, so draw at the window's own scale.
  const float scale = dpi_ ? static_cast<float>(dpi_) / 96.0f : 1.0f;
  auto *format = device_.GetTextFormat(
      L"Segoe UI", 14.0f, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_CENTER,
      DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_WORD_WRAPPING_NO_WRAP);
  if (!format)
    throw std::runtime_error("Mode text format unavailable");
  const std::optional<bool> values[] = {value->chinese,
                                        value->chinese_punctuation,
                                        value->fullwidth};
  target->BeginDraw();
  target->Clear(D2D1::ColorF(palette_.surface.r, palette_.surface.g,
                             palette_.surface.b, palette_.surface.a));
  for (int i = 0; i < 6; ++i) {
    const D2D1_RECT_F cell{
        static_cast<float>((i % 2) * layout_->cell_width) / scale,
        static_cast<float>((i / 2) * layout_->cell_height) / scale,
        static_cast<float>((i % 2 + 1) * layout_->cell_width) / scale,
        static_cast<float>((i / 2 + 1) * layout_->cell_height) / scale};
    const D2D1_ROUNDED_RECT rounded{{cell.left + 2.0f, cell.top + 2.0f,
                                     cell.right - 2.0f, cell.bottom - 2.0f},
                                    palette_.item_radius, palette_.item_radius};
    const auto current = values[i / 2];
    // The confirmed half of each pair reads as selected; unknown state stays
    // neutral rather than guessing which half the host applied.
    const bool active = current && *current == (i % 2 == 0);
    target->FillRoundedRectangle(rounded,
                                 brush(active ? palette_.selected : palette_.hover));
    target->DrawRoundedRectangle(rounded, brush(palette_.border),
                                 palette_.border_width);
    std::wstring text = labels[i];
    text += !current ? L" ?" : (active ? L" \u2713" : L"");
    target->DrawText(text.c_str(), static_cast<UINT32>(text.size()), format,
                     rounded.rect,
                     brush(active ? palette_.accent : palette_.text));
  }
  const HRESULT drawn = target->EndDraw();
  if (drawn == D2DERR_RECREATE_TARGET) {
    device_.DiscardTarget();
    return;
  }
  if (FAILED(drawn))
    throw std::runtime_error("Mode drawing failed");
  painted_ = value;
}
std::optional<ModeClick> ModeWindow::hit(int x, int y) {
  if (!painted_ || !layout_ || !IsWindowVisible(window_))
    return {};
  const auto index = layout_->hit(x, y);
  if (!index)
    return {};
  const auto value = reader_();
  if (!value || !same(value->lease, painted_->lease))
    return {};
  return ModeClick{value->lease, commands[*index]};
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
      if (self->pressed_) {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
        if (!TrackMouseEvent(&track))
          self->pressed_.reset();
      }
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
    case WM_MOUSELEAVE:
      self->pressed_.reset();
      return 0;
    case WM_DPICHANGED:
    case WM_DISPLAYCHANGE:
    case WM_SETTINGCHANGE:
      self->layout_.reset();
      self->monitor_ = nullptr;
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

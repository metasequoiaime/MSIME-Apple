#include "TrayMenuWindow.h"
#include <stdexcept>

namespace msime::windows {
namespace {
constexpr wchar_t class_name[] = L"MSIME.Client.Preview.TrayMenu";
constexpr size_t no_row = static_cast<size_t>(-1);
// Affect only this UI operation; restore the caller's thread context even on
// failure.
struct DpiScope {
  DPI_AWARENESS_CONTEXT previous;
  DpiScope()
      : previous(SetThreadDpiAwarenessContext(
            DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {
    if (!previous)
      throw std::runtime_error("Per-monitor DPI unavailable");
  }
  ~DpiScope() { SetThreadDpiAwarenessContext(previous); }
};
struct Painting {
  HWND window;
  PAINTSTRUCT state{};
  HDC dc;
  explicit Painting(HWND value)
      : window(value), dc(BeginPaint(window, &state)) {}
  ~Painting() { EndPaint(window, &state); }
};
std::wstring wide(const std::string &text) {
  if (text.empty() || text.size() > 256)
    throw std::invalid_argument("Invalid tray menu label");
  const int count =
      MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), nullptr, 0);
  if (!count)
    throw std::invalid_argument("Invalid tray menu label");
  std::wstring result(static_cast<size_t>(count), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), result.data(),
                          count) != count)
    throw std::invalid_argument("Invalid tray menu label");
  return result;
}
} // namespace

TrayMenuWindow::Apartment::Apartment() {
  const HRESULT entered =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  // S_FALSE only means this thread was already inside the same apartment; the
  // reference still has to be released. A different mode is left untouched.
  if (FAILED(entered) && entered != RPC_E_CHANGED_MODE)
    throw std::runtime_error("Tray menu apartment unavailable");
  owned = entered != RPC_E_CHANGED_MODE;
}
TrayMenuWindow::Apartment::~Apartment() {
  if (owned)
    CoUninitialize();
}

TrayMenuWindow::TrayMenuWindow(TrayMenuCapabilities capabilities,
                               Command command, ToolbarState toolbar_state)
    : capabilities_(capabilities), command_(std::move(command)),
      toolbar_state_(std::move(toolbar_state)) {
  if (!command_ || !toolbar_state_)
    throw std::invalid_argument("Missing tray menu callback");
  DpiScope dpi_scope;
  WNDCLASSEXW descriptor{};
  descriptor.cbSize = sizeof(descriptor);
  descriptor.lpfnWndProc = procedure;
  descriptor.hInstance = GetModuleHandleW(nullptr);
  descriptor.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
  descriptor.lpszClassName = class_name;
  // This process owns the class; no per-window unregister/re-register race.
  if (!RegisterClassExW(&descriptor) &&
      GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
    throw std::runtime_error("Tray menu class unavailable");
  // No redirection bitmap: the card is composed with per-pixel alpha, which is
  // what gives it rounded corners instead of a rectangular window cut-out.
  window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW |
                                WS_EX_TOPMOST | WS_EX_NOREDIRECTIONBITMAP,
                            class_name, L"", WS_POPUP, 0, 0, 1, 1, nullptr,
                            nullptr, descriptor.hInstance, this);
  if (!window_)
    throw std::runtime_error("Tray menu window unavailable");
}
TrayMenuWindow::~TrayMenuWindow() {
  if (window_)
    DestroyWindow(window_);
}
void TrayMenuWindow::set_palette(CandidatePalette palette) {
  palette_ = std::move(palette);
  if (window_)
    InvalidateRect(window_, nullptr, FALSE);
}
bool TrayMenuWindow::visible() const {
  return window_ && IsWindowVisible(window_);
}
void TrayMenuWindow::hide() {
  hovered_ = no_row;
  items_.clear();
  if (window_)
    ShowWindow(window_, SW_HIDE);
}
bool TrayMenuWindow::open(int icon_center_x, int icon_top) noexcept {
  try {
    show(icon_center_x, icon_top);
    return visible();
  } catch (...) {
    // Appearance must not be fatal: leave failed_ alone and report no menu.
    hide();
    return false;
  }
}
bool TrayMenuWindow::pointer_inside() const noexcept {
  POINT cursor{};
  RECT bounds{};
  if (!window_ || !GetCursorPos(&cursor) || !GetWindowRect(window_, &bounds))
    return false;
  return PtInRect(&bounds, cursor) != FALSE;
}
void TrayMenuWindow::show(int icon_center_x, int icon_top) {
  DpiScope dpi_scope;
  if (failed_) {
    hide();
    return;
  }
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(MonitorFromPoint({icon_center_x, icon_top},
                                        MONITOR_DEFAULTTONEAREST),
                       &monitor))
    throw std::runtime_error("Tray menu monitor unavailable");
  // Read the toolbar state once per opening: the row shows what the Server
  // reports now, not what a click later assumed.
  items_ = tray_menu_items(capabilities_, toolbar_state_());
  hovered_ = no_row;
  const auto &work = monitor.rcWork;
  dpi_ = GetDpiForWindow(window_);
  const auto bounds =
      tray_menu_bounds(icon_center_x, icon_top, work.left, work.top, work.right,
                       work.bottom, dpi_, tray_menu_size(items_.size(), metrics_));
  if (!SetWindowPos(window_, HWND_TOPMOST, bounds.x, bounds.y, bounds.width,
                    bounds.height, SWP_NOACTIVATE | SWP_SHOWWINDOW))
    throw std::runtime_error("Tray menu positioning failed");
  InvalidateRect(window_, nullptr, FALSE);
}
std::optional<size_t> TrayMenuWindow::hit(int x, int y) const {
  if (items_.empty() || !dpi_)
    return std::nullopt;
  const double scale = static_cast<double>(dpi_) / 96.0;
  return tray_menu_hit(x / scale, y / scale, items_, metrics_);
}
void TrayMenuWindow::choose(size_t index) {
  if (index >= items_.size() || !items_[index].available)
    return;
  const auto command = items_[index].command;
  // A command that could not run leaves the menu open, so a failure is not
  // mistaken for an applied action.
  if (command_(command))
    hide();
  else if (window_)
    InvalidateRect(window_, nullptr, FALSE);
}
void TrayMenuWindow::paint() {
  DpiScope dpi_scope;
  Painting painting(window_);
  if (!painting.dc)
    throw std::runtime_error("Tray menu painting unavailable");
  if (items_.empty()) {
    hide();
    return;
  }
  if (!device_.EnsureForComposition(window_))
    throw std::runtime_error("Tray menu device unavailable");
  auto *target = device_.GetRenderTarget();
  if (!target)
    throw std::runtime_error("Tray menu render target unavailable");
  auto brush = [&](const CandidateColor &color) {
    auto *created = device_.GetSolidColorBrush(
        D2D1::ColorF(color.r, color.g, color.b, color.a));
    if (!created)
      throw std::runtime_error("Tray menu brush unavailable");
    return created;
  };
  auto *label_format = device_.GetTextFormat(
      L"Segoe UI", 14.0f, DWRITE_FONT_WEIGHT_NORMAL,
      DWRITE_TEXT_ALIGNMENT_LEADING, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
      DWRITE_WORD_WRAPPING_NO_WRAP);
  auto *state_format = device_.GetTextFormat(
      L"Segoe UI", 14.0f, DWRITE_FONT_WEIGHT_NORMAL,
      DWRITE_TEXT_ALIGNMENT_TRAILING, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
      DWRITE_WORD_WRAPPING_NO_WRAP);
  if (!label_format || !state_format)
    throw std::runtime_error("Tray menu text format unavailable");
  const auto size = target->GetSize();
  const float inset = palette_.border_width / 2.0f;
  target->BeginDraw();
  // Clear to nothing: only the rounded card is opaque, so the corners stay
  // transparent rather than showing a square window edge.
  target->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
  const D2D1_ROUNDED_RECT card{
      {inset, inset, size.width - inset, size.height - inset},
      static_cast<float>(metrics_.radius), static_cast<float>(metrics_.radius)};
  target->FillRoundedRectangle(card, brush(palette_.surface));
  target->DrawRoundedRectangle(card, brush(palette_.border),
                               palette_.border_width);
  for (size_t index = 0; index < items_.size(); ++index) {
    const auto row = tray_menu_row(index, items_.size(), metrics_);
    const D2D1_RECT_F rect{static_cast<float>(metrics_.padding),
                           static_cast<float>(row.top),
                           size.width - static_cast<float>(metrics_.padding),
                           static_cast<float>(row.bottom)};
    if (index == hovered_ && items_[index].available)
      target->FillRoundedRectangle({rect, palette_.item_radius,
                                    palette_.item_radius},
                                   brush(palette_.hover));
    const auto label = wide(items_[index].label);
    // An unavailable row is dimmed with the muted token instead of hidden.
    target->DrawText(label.c_str(), static_cast<UINT32>(label.size()),
                     label_format,
                     D2D1_RECT_F{rect.left + 8.0f, rect.top, rect.right,
                                 rect.bottom},
                     brush(items_[index].available ? palette_.text
                                                   : palette_.number));
    if (!items_[index].toggle)
      continue;
    const wchar_t *state = items_[index].checked ? L"✓" : L"";
    target->DrawText(state, static_cast<UINT32>(wcslen(state)), state_format,
                     D2D1_RECT_F{rect.left, rect.top, rect.right - 8.0f,
                                 rect.bottom},
                     brush(palette_.accent));
  }
  const HRESULT drawn = target->EndDraw();
  // A composition swap chain only reaches the screen once it is presented.
  if (SUCCEEDED(drawn) && FAILED(device_.Present()))
    throw std::runtime_error("Tray menu presentation failed");
  if (drawn == D2DERR_RECREATE_TARGET) {
    // Losing the device is not a presentation failure; rebuild on the next
    // opening rather than hiding a live menu.
    device_.DiscardTarget();
    return;
  }
  if (FAILED(drawn))
    throw std::runtime_error("Tray menu drawing failed");
}
LRESULT CALLBACK TrayMenuWindow::procedure(HWND window, UINT message,
                                           WPARAM wparam,
                                           LPARAM lparam) noexcept {
  auto *self = reinterpret_cast<TrayMenuWindow *>(
      GetWindowLongPtrW(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    self = static_cast<TrayMenuWindow *>(
        reinterpret_cast<CREATESTRUCTW *>(lparam)->lpCreateParams);
    SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    self->window_ = window;
  }
  if (self) {
    try {
      switch (message) {
      case WM_MOUSEACTIVATE:
        // The menu acts on clicks without taking focus from the application
        // the user is typing into.
        return MA_NOACTIVATE;
      case WM_MOUSEMOVE: {
        const auto row = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        const size_t hovered = row ? *row : no_row;
        if (hovered != self->hovered_) {
          self->hovered_ = hovered;
          InvalidateRect(window, nullptr, FALSE);
          TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
          TrackMouseEvent(&track);
        }
        return 0;
      }
      case WM_MOUSELEAVE:
        if (self->hovered_ != no_row) {
          self->hovered_ = no_row;
          InvalidateRect(window, nullptr, FALSE);
        }
        return 0;
      case WM_LBUTTONUP: {
        const auto row = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        if (row)
          self->choose(*row);
        return 0;
      }
      case WM_KILLFOCUS:
        self->hide();
        return 0;
      case WM_PAINT:
        self->paint();
        return 0;
      }
    } catch (...) {
      self->failed_ = true;
      self->hide(); // No exception may cross the Win32 callback.
      return 0;
    }
  }
  return DefWindowProcW(window, message, wparam, lparam);
}
} // namespace msime::windows

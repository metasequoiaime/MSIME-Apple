#include "FloatingToolbarWindow.h"
#include "FloatingToolbarPlacement.h"
#include <stdexcept>
#include <windowsx.h>
#include <vector>

namespace msime::windows {
namespace {
constexpr wchar_t kClassName[] = L"MSIME.Client.Preview.FloatingToolbar";
constexpr int kWidth = 732;
constexpr int kHeight = 52;
int dpi_scale(HWND window, int value) {
  const UINT dpi = GetDpiForWindow(window);
  return MulDiv(value, static_cast<int>(dpi ? dpi : USER_DEFAULT_SCREEN_DPI), USER_DEFAULT_SCREEN_DPI);
}
bool same(const FocusLease &a, const FocusLease &b) {
  return a.epoch == b.epoch && a.token == b.token &&
         same_ticket(a.transport, b.transport);
}
// The preference array is ordered as character_set, punctuation, fullwidth,
// emoji, screen_keyboard, settings. Language is always present; the other
// buttons follow the shared shell order.
std::vector<int> slots(const std::array<bool, 6> &items) {
  std::vector<int> result;
  result.push_back(0); // language
  if (items[2]) result.push_back(1); // fullwidth
  if (items[1]) result.push_back(2); // punctuation
  if (items[0]) result.push_back(3); // character set
  if (items[3]) result.push_back(4); // emoji
  if (items[4]) result.push_back(5); // screen keyboard
  if (items[5]) result.push_back(6); // settings
  result.push_back(7); // voice
  result.push_back(8); // about
  result.push_back(9); // hide
  return result;
}
} // namespace

FloatingToolbarWindow::FloatingToolbarWindow(Reader reader, Click click)
    : reader_(std::move(reader)), click_(std::move(click)) {
  if (!reader_ || !click_) throw std::invalid_argument("Missing toolbar callback");
  WNDCLASSEXW type{};
  type.cbSize = sizeof(type);
  type.lpfnWndProc = procedure;
  type.hInstance = GetModuleHandleW(nullptr);
  type.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
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
void FloatingToolbarWindow::hide() {
  shown_.reset();
  shown_character_set_.reset();
  if (window_) ShowWindow(window_, SW_HIDE);
}
void FloatingToolbarWindow::refresh(bool enabled) {
  if (failed_) return;
  try {
    if (!enabled) { hide(); return; }
    const auto value = reader_();
    if (!value) { hide(); return; }
    const auto character_set = character_set_reader_ ? character_set_reader_()
                                                     : std::nullopt;
    const bool changed = !shown_ || !same(shown_->lease, value->lease) ||
                         shown_->chinese != value->chinese ||
                         shown_->chinese_punctuation != value->chinese_punctuation ||
                         shown_->fullwidth != value->fullwidth ||
                         shown_character_set_ != character_set;
    if (!changed && IsWindowVisible(window_)) return;
    shown_ = value;
    shown_character_set_ = character_set;
    RECT work{};
    // Before the first placement the toolbar has no position of its own, so it
    // follows the focused window's monitor. After that it stays on whichever
    // screen the user dragged it to - clamping a dragged toolbar against the
    // foreground window's monitor would drag it back across the desktop.
    const HMONITOR monitor =
        placed_ ? MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST)
                : MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTOPRIMARY);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    if (!GetMonitorInfoW(monitor, &info)) throw std::runtime_error("Toolbar monitor unavailable");
    work = info.rcWork;
    const int width = dpi_scale(window_, static_cast<int>((16 + 72 * slots(items_).size()) * scale_));
    const int height = dpi_scale(window_, static_cast<int>(kHeight * scale_));
    const int margin = dpi_scale(window_, 20);
    FloatingToolbarPlacementInput placement;
    placement.width = width;
    placement.height = height;
    placement.margin = margin;
    placement.work_left = work.left;
    placement.work_top = work.top;
    placement.work_right = work.right;
    placement.work_bottom = work.bottom;
    placement.placed = placed_;
    RECT current{};
    if (placed_ && GetWindowRect(window_, &current)) {
      placement.current_x = current.left;
      placement.current_y = current.top;
    } else {
      placement.placed = false;
    }
    const auto placed = floating_toolbar_placement(placement);
    if (!SetWindowPos(window_, HWND_TOPMOST, placed.x, placed.y, width, height,
                      SWP_NOACTIVATE | SWP_SHOWWINDOW))
      throw std::runtime_error("Toolbar positioning failed");
    // Only after the move succeeded, so a failed first placement retries the
    // corner rather than preserving a position the window never took.
    placed_ = true;
    InvalidateRect(window_, nullptr, FALSE);
  } catch (...) { failed_ = true; hide(); }
}
FloatingToolbarWindow::Apartment::Apartment() {
  const HRESULT entered =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(entered) && entered != RPC_E_CHANGED_MODE)
    throw std::runtime_error("Toolbar apartment unavailable");
  owned = entered != RPC_E_CHANGED_MODE;
}
FloatingToolbarWindow::Apartment::~Apartment() {
  if (owned)
    CoUninitialize();
}
void FloatingToolbarWindow::set_palette(CandidatePalette palette) {
  palette_ = std::move(palette);
  if (window_)
    InvalidateRect(window_, nullptr, FALSE);
}
void FloatingToolbarWindow::paint() {
  PAINTSTRUCT state{};
  const HDC dc = BeginPaint(window_, &state);
  if (!dc)
    return;
  struct End {
    HWND window;
    PAINTSTRUCT &state;
    ~End() { EndPaint(window, &state); }
  } end{window_, state};
  if (!device_.EnsureForWindow(window_))
    throw std::runtime_error("Toolbar device unavailable");
  auto *target = device_.GetRenderTarget();
  if (!target)
    throw std::runtime_error("Toolbar render target unavailable");
  auto brush = [&](const CandidateColor &color) {
    auto *created = device_.GetSolidColorBrush(
        D2D1::ColorF(color.r, color.g, color.b, color.a));
    if (!created)
      throw std::runtime_error("Toolbar brush unavailable");
    return created;
  };
  const float unit = static_cast<float>(dpi_scale(window_, 1)) * static_cast<float>(scale_);
  auto *format = device_.GetTextFormat(
      L"Segoe UI", static_cast<float>(font_size_) * unit, DWRITE_FONT_WEIGHT_NORMAL,
      DWRITE_TEXT_ALIGNMENT_CENTER, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
      DWRITE_WORD_WRAPPING_NO_WRAP);
  if (!format)
    throw std::runtime_error("Toolbar text format unavailable");
  const auto size = target->GetSize();
  target->BeginDraw();
  target->Clear(D2D1::ColorF(palette_.surface.r, palette_.surface.g,
                             palette_.surface.b, palette_.surface.a));
  const float inset = palette_.border_width * unit / 2.0f;
  target->DrawRoundedRectangle(
      {{inset, inset, size.width - inset, size.height - inset}, palette_.radius * unit,
       palette_.radius * unit},
      brush(palette_.border), palette_.border_width * unit);
  const auto value = reader_();
  if (value && shown_ && same(value->lease, shown_->lease)) {
    // An unreported mode shows a question mark rather than a guessed state.
    auto label = [](const std::optional<bool> &state, const wchar_t *on,
                    const wchar_t *off) {
      return !state ? L"?" : (*state ? on : off);
    };
    const wchar_t *labels[] = {
        label(value->chinese, L"\u4e2d", L"\u82f1"),
        label(value->fullwidth, L"\u5168", L"\u534a"),
        label(value->chinese_punctuation, L"\u3002", L"."),
        !shown_character_set_ ? L"?" : (*shown_character_set_ ? L"\u7e41" : L"\u7b80"),
        items_[3] ? L"😀" : L"", items_[4] ? L"⌨" : L"",
        items_[5] ? L"\u8bbe" : L"", L"🎙", L"?", L"×"};
    const auto active = slots(items_);
    for (size_t i = 0; i < active.size(); ++i) {
      const int button = active[i];
      const D2D1_RECT_F cell{8.0f * unit + static_cast<float>(i) * 72.0f * unit, 8.0f * unit,
                             (72.0f + static_cast<float>(i) * 72.0f) * unit, 44.0f * unit};
      target->DrawText(labels[button], static_cast<UINT32>(wcslen(labels[button])), format,
                       cell, brush(palette_.text));
    }
  }
  const HRESULT drawn = target->EndDraw();
  if (drawn == D2DERR_RECREATE_TARGET) {
    device_.DiscardTarget();
    return;
  }
  if (FAILED(drawn))
    throw std::runtime_error("Toolbar drawing failed");
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
    case WM_DPICHANGED:
      if (self->shown_) self->refresh(true);
      return 0;
    case WM_PAINT: self->paint(); return 0;
    case WM_LBUTTONDOWN:
      ReleaseCapture();
      SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      return 0;
    case WM_LBUTTONUP: {
      const auto value = self->reader_();
      const int x = GET_X_LPARAM(l);
      const int unit = dpi_scale(window, 1);
      const auto active = slots(self->items_);
      if (value && x >= 8 * unit && x < static_cast<int>((8 + 72 * active.size()) * unit)) {
        const size_t position = static_cast<size_t>((x - 8 * unit) / (72 * unit));
        if (position >= active.size()) return 0;
        const int slot = active[position];
        if (slot == 0) self->click_(ModeClick{value->lease, WorkerMode::Chinese});
        else if (slot == 1) self->click_(ModeClick{
            value->lease, value->fullwidth && *value->fullwidth
                                     ? WorkerMode::Halfwidth
                                     : WorkerMode::Fullwidth});
        else if (slot == 2) self->click_(ModeClick{
            value->lease, value->chinese_punctuation && *value->chinese_punctuation
                                     ? WorkerMode::AsciiPunctuation
                                     : WorkerMode::ChinesePunctuation});
        else if (slot == 3 && self->character_set_action_)
          self->character_set_action_();
        else if (slot == 4 && self->emoji_action_)
          self->emoji_action_();
        else if (slot == 5 && self->keyboard_action_)
          self->keyboard_action_();
        else if (slot == 6 && self->settings_action_)
          self->settings_action_();
        else if (slot == 7 && self->voice_action_)
          self->voice_action_();
        else if (slot == 8 && self->about_action_)
          self->about_action_();
        else if (slot == 9 && self->hide_action_)
          self->hide_action_();
      }
      return 0;
    }
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

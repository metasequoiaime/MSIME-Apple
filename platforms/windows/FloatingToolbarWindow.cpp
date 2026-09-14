#include "FloatingToolbarWindow.h"
#include "FloatingToolbarPlacement.h"
#include "ToolbarIcons.h"
#include "ToolbarLayout.h"
#include "WindowShadow.h"
#include "IconFont.h"
#include <algorithm>
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
  // A hidden toolbar has no pointer over it; leaving these set would show a
  // stale highlight the next time it appears.
  hovered_.reset();
  pressed_.reset();
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
    const auto metrics = toolbar_metrics(static_cast<double>(font_size_));
    const int width = dpi_scale(
        window_, static_cast<int>(
                     toolbar_window_width(slots(items_).size(), metrics) *
                     scale_));
    const int height = dpi_scale(
        window_, static_cast<int>(toolbar_window_height(metrics) * scale_));
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
  // Composition rather than an hwnd target: the shadow falls outside the bar,
  // so the window has to carry per-pixel alpha where it is nothing but shadow.
  if (!device_.EnsureForComposition(window_))
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
  const auto bar = toolbar_metrics(static_cast<double>(font_size_));
  const auto card = toolbar_card(slots(items_).size(), bar);
  const D2D1_RECT_F card_rect{
      static_cast<float>(card.left) * unit, static_cast<float>(card.top) * unit,
      static_cast<float>(card.right) * unit,
      static_cast<float>(card.bottom) * unit};
  target->BeginDraw();
  // Transparent, not the surface colour: everything outside the bar is either
  // shadow or the desktop showing through.
  target->Clear(D2D1::ColorF(0, 0.0f));
  draw_window_shadow(target, card_rect, palette_.radius * unit,
                     static_cast<float>(bar.shadow.scale));
  const float inset = palette_.border_width * unit / 2.0f;
  const D2D1_ROUNDED_RECT body{{card_rect.left + inset, card_rect.top + inset,
                                card_rect.right - inset,
                                card_rect.bottom - inset},
                               palette_.radius * unit, palette_.radius * unit};
  target->FillRoundedRectangle(body, brush(palette_.surface));
  target->DrawRoundedRectangle(body, brush(palette_.border),
                               palette_.border_width * unit);
  const auto value = reader_();
  if (value && shown_ && same(value->lease, shown_->lease)) {
    auto *factory = device_.GetDWriteFactory();
    const wchar_t *icon_family = icon_font_family(factory);
    // Each button's two-way mode, in slot order. An absent state means the
    // Server has not reported it, and the icon shows a question mark rather
    // than asserting a mode the user is not actually in.
    const std::optional<bool> states[] = {
        value->chinese,
        value->fullwidth,
        value->chinese_punctuation,
        shown_character_set_,
        std::nullopt, std::nullopt, std::nullopt,
        std::nullopt, std::nullopt, std::nullopt};
    const auto active = slots(items_);
    const auto layout = toolbar_metrics(static_cast<double>(font_size_));
    // The drag strip and the divider that separates it from the buttons. The
    // strip is the only part that drags, so it has to be visible; upstream
    // draws it in the accent colour. Both follow the bar height so they stay
    // centred when the icon size changes.
    const auto height = static_cast<float>(layout.height);
    const float top = card_rect.top;
    const float handle_left = card_rect.left + 3.0f * unit;
    const D2D1_ROUNDED_RECT handle{{handle_left, top + height * 0.269f * unit,
                                    handle_left + 2.0f * unit,
                                    top + height * 0.731f * unit},
                                   1.0f * unit, 1.0f * unit};
    target->FillRoundedRectangle(handle, brush(palette_.accent));
    const float divider =
        card_rect.left + static_cast<float>(layout.handle - 1.0) * unit;
    target->DrawLine({divider, top + height * 0.231f * unit},
                     {divider, top + height * 0.769f * unit},
                     brush(palette_.border), 1.0f * unit);
    for (size_t i = 0; i < active.size(); ++i) {
      const int button = active[i];
      const auto box = toolbar_cell(i, layout);
      const D2D1_RECT_F cell{static_cast<float>(box.left) * unit,
                             static_cast<float>(box.top) * unit,
                             static_cast<float>(box.right) * unit,
                             static_cast<float>(box.bottom) * unit};
      // Hover and press fills, so a button looks like one. Pressed is drawn
      // with the selected colour rather than a darker hover, matching the card.
      if (hovered_ == i) {
        const bool down = pressed_ == i;
        const D2D1_ROUNDED_RECT fill{{cell.left + 2.0f * unit, cell.top,
                                      cell.right - 2.0f * unit, cell.bottom},
                                     palette_.item_radius * unit,
                                     palette_.item_radius * unit};
        target->FillRoundedRectangle(
            fill, brush(down ? palette_.selected : palette_.hover));
      }
      const auto icon = toolbar_icon(button, states[button], language_);
      // Draw the glyph only when the installed icon font really has it;
      // otherwise the text fallback, which is always readable.
      const bool glyph = icon.codepoint && icon_family &&
                         icon_font_has(factory, icon_family, icon.codepoint);
      const wchar_t text[] = {icon.codepoint, L'\0'};
      auto *cell_format =
          glyph ? device_.GetTextFormat(
                      icon_family, static_cast<float>(font_size_) * unit,
                      DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_CENTER,
                      DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
                      DWRITE_WORD_WRAPPING_NO_WRAP)
                : format;
      if (!cell_format)
        cell_format = format;
      const wchar_t *drawn_text = glyph ? text : icon.fallback;
      const auto length = static_cast<UINT32>(wcslen(drawn_text));
      if (!length)
        continue;
      target->DrawText(drawn_text, length, cell_format, cell,
                       brush(palette_.text));
      // Dedicated English underlines its "En". Upstream insets the line by a
      // twelfth of the cell and floors both the offset and the stroke, so it
      // stays a visible line rather than thinning away at small icon sizes.
      if (icon.underline && !glyph) {
        const float size = static_cast<float>(font_size_) * unit;
        const float side = (cell.right - cell.left) * 0.08f;
        const float y = cell.bottom - (std::max)(2.0f * unit, size * 0.12f);
        target->DrawLine({cell.left + side, y}, {cell.right - side, y},
                         brush(palette_.text),
                         (std::max)(1.0f * unit, size * 0.06f));
      }
    }
  }
  const HRESULT drawn = target->EndDraw();
  // A composition swap chain only reaches the screen once it is presented.
  if (SUCCEEDED(drawn) && FAILED(device_.Present()))
    throw std::runtime_error("Toolbar presentation failed");
  if (drawn == D2DERR_RECREATE_TARGET) {
    device_.DiscardTarget();
    InvalidateRect(window_, nullptr, FALSE);
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
    case WM_LBUTTONDOWN: {
      // Only the strip left of the first button drags. Treating the whole
      // window as a caption meant a press on a button entered the system move
      // loop, and the click below only ran for whatever button-up survived it.
      const int unit = dpi_scale(window, 1);
      const auto drag = toolbar_metrics(static_cast<double>(self->font_size_));
      if (toolbar_is_drag_strip(
              static_cast<double>(GET_X_LPARAM(l)) / unit, drag)) {
        ReleaseCapture();
        SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        return 0;
      }
      // Pressing a button shows it pressed until the release is handled.
      self->pressed_ = self->hovered_;
      if (self->pressed_)
        InvalidateRect(window, nullptr, FALSE);
      return 0;
    }
    case WM_SETCURSOR:
      // Show the move cursor over the drag strip only, so the buttons keep the
      // ordinary arrow and the strip advertises what it does.
      if (LOWORD(l) == HTCLIENT) {
        POINT cursor{};
        RECT bounds{};
        if (GetCursorPos(&cursor) && ScreenToClient(window, &cursor) &&
            GetClientRect(window, &bounds) &&
            toolbar_is_drag_strip(
                static_cast<double>(cursor.x) / dpi_scale(window, 1),
                toolbar_metrics(static_cast<double>(self->font_size_)))) {
          SetCursor(LoadCursorW(nullptr, IDC_SIZEALL));
          return TRUE;
        }
      }
      break;
    case WM_MOUSEMOVE: {
      // Hover feedback needs to know where the pointer is; without tracking,
      // the buttons gave no sign that they were buttons at all.
      const int x = GET_X_LPARAM(l);
      const int unit = dpi_scale(window, 1);
      const auto active = slots(self->items_);
      const auto layout = toolbar_metrics(static_cast<double>(self->font_size_));
      const auto hovered = toolbar_button_at(
          static_cast<double>(x) / unit, active.size(), layout);
      if (hovered != self->hovered_) {
        self->hovered_ = hovered;
        InvalidateRect(window, nullptr, FALSE);
      }
      // Ask for one leave message so the highlight is dropped when the pointer
      // goes elsewhere; without it the last hovered button stays lit.
      if (!self->tracking_mouse_) {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
        self->tracking_mouse_ = TrackMouseEvent(&track) != FALSE;
      }
      return 0;
    }
    case WM_MOUSELEAVE:
      self->tracking_mouse_ = false;
      if (self->hovered_) {
        self->hovered_.reset();
        InvalidateRect(window, nullptr, FALSE);
      }
      return 0;
    case WM_LBUTTONUP: {
      // Release always clears the pressed look, whether or not the release
      // lands on a button - otherwise a press that slid off stays lit.
      if (self->pressed_) {
        self->pressed_.reset();
        InvalidateRect(window, nullptr, FALSE);
      }
      const auto value = self->reader_();
      const int x = GET_X_LPARAM(l);
      const int unit = dpi_scale(window, 1);
      const auto active = slots(self->items_);
      const auto layout = toolbar_metrics(static_cast<double>(self->font_size_));
      const auto position_at =
          toolbar_button_at(static_cast<double>(x) / unit, active.size(), layout);
      if (value && position_at) {
        const size_t position = *position_at;
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

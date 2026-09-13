#include "CandidateWindow.h"
#include "CandidateWheel.h"
#include "CursorResource.h"
#include <algorithm>

namespace msime::windows {
namespace {
bool installed_font(const std::wstring &family) {
  HDC dc = GetDC(nullptr);
  if (!dc) return false;
  LOGFONTW logfont{};
  wcsncpy_s(logfont.lfFaceName, family.c_str(), LF_FACESIZE - 1);
  bool found = false;
  EnumFontFamiliesExW(dc, &logfont,
      [](const LOGFONTW *, const TEXTMETRICW *, DWORD, LPARAM data) -> int {
        *reinterpret_cast<bool *>(data) = true;
        return 0;
      }, reinterpret_cast<LPARAM>(&found), 0);
  ReleaseDC(nullptr, dc);
  return found;
}
constexpr wchar_t class_name[] = L"MSIME.Client.Preview.Candidates";
// Affect only this UI operation; restore the caller's thread context even on
// failure. The created HWND retains PMv2 awareness for its entire lifetime.
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
struct Font {
  HDC dc;
  HFONT font;
  HGDIOBJ previous;
  Font(HDC target, int height, const wchar_t *family = L"Segoe UI")
      : dc(target), font(CreateFontW(-height, 0, 0, 0, FW_NORMAL, FALSE, FALSE,
                                     FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                                     CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                                     DEFAULT_PITCH, family)),
        previous(nullptr) {
    if (!font)
      throw std::runtime_error("Candidate font unavailable");
    previous = SelectObject(dc, font);
    if (!previous || previous == HGDI_ERROR) {
      DeleteObject(font);
      throw std::runtime_error("Candidate font selection failed");
    }
  }
  ~Font() {
    SelectObject(dc, previous);
    DeleteObject(font);
  }
};
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
// Text width in device independent pixels. DirectWrite is the same engine the
// renderer draws with, so the card cannot be sized for a different shaping.
double measured_width(msimeui::DeviceResources &device, const std::wstring &text,
                      const std::wstring &family, float size) {
  if (text.empty() || size <= 0.0f)
    return 0.0;
  auto *factory = device.GetDWriteFactory();
  auto *format = device.GetTextFormat(
      family, size, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING,
      DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_WORD_WRAPPING_NO_WRAP);
  Microsoft::WRL::ComPtr<IDWriteTextLayout> layout;
  DWRITE_TEXT_METRICS metrics{};
  if (factory && format &&
      SUCCEEDED(factory->CreateTextLayout(text.c_str(),
                                          static_cast<UINT32>(text.size()),
                                          format, 8192.0f, size * 4.0f,
                                          layout.GetAddressOf())) &&
      layout && SUCCEEDED(layout->GetMetrics(&metrics)))
    return metrics.widthIncludingTrailingWhitespace;
  // Without a usable factory the card is still sized, just less precisely.
  return static_cast<double>(text.size()) * static_cast<double>(size) * 0.92;
}
struct Painting {
  HWND window;
  PAINTSTRUCT state{};
  HDC dc;
  explicit Painting(HWND value)
      : window(value), dc(BeginPaint(window, &state)) {}
  ~Painting() { EndPaint(window, &state); }
};
struct PopupMenu {
  HMENU handle = nullptr;
  ~PopupMenu() {
    if (handle)
      DestroyMenu(handle);
  }
  PopupMenu() = default;
  explicit PopupMenu(HMENU value) : handle(value) {}
  PopupMenu(const PopupMenu &) = delete;
  PopupMenu &operator=(const PopupMenu &) = delete;
  PopupMenu(PopupMenu &&other) noexcept : handle(other.handle) {
    other.handle = nullptr;
  }
  PopupMenu &operator=(PopupMenu &&other) noexcept {
    if (this != &other) {
      if (handle)
        DestroyMenu(handle);
      handle = other.handle;
      other.handle = nullptr;
    }
    return *this;
  }
};
constexpr UINT menu_pin = 1;
constexpr UINT menu_remove = 2;
constexpr UINT menu_fix_first = 100;
constexpr UINT menu_fix_last = menu_fix_first + 4;
constexpr UINT menu_clear_fix = 105;
void append_menu(HMENU menu, UINT flags, UINT_PTR command,
                 const wchar_t *label) {
  if (!AppendMenuW(menu, flags, command, label))
    throw std::runtime_error("Candidate context menu unavailable");
}
} // namespace
CandidateWindow::CandidateWindow(Reader reader, Click click, unsigned font_size,
                                 unsigned preedit_font_size,
                                 std::optional<COLORREF> text_color,
                                 std::string font_family,
                                 std::vector<std::string> fallback_fonts,
                                 std::optional<bool> dark_theme,
                                 bool horizontal, bool show_preedit, Page page)
    : reader_(std::move(reader)), click_(std::move(click)), page_(std::move(page)),
      font_size_(font_size),
      preedit_font_size_(preedit_font_size), text_color_(text_color),
      palette_(dark_theme.value_or(false) ? CandidatePalette{}
                                          : candidate_light_palette()),
      font_family_(wide(font_family)), dark_theme_(dark_theme), horizontal_(horizontal),
      show_preedit_(show_preedit) {
  if (font_family_.empty() || font_family_.size() > 128)
    throw std::invalid_argument("Invalid candidate font family");
  if (font_size_ < 12 || font_size_ > 32 || preedit_font_size_ < 12 ||
      preedit_font_size_ > 32)
    throw std::invalid_argument("Invalid candidate font size");
  if (!installed_font(font_family_)) {
    for (const auto &fallback : fallback_fonts) {
      auto candidate = wide(fallback);
      if (!candidate.empty() && candidate.size() <= 128 && installed_font(candidate)) {
        font_family_ = std::move(candidate);
        break;
      }
    }
  }
  if (!reader_)
    throw std::invalid_argument("Missing candidate reader");
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
    throw std::runtime_error("Candidate class unavailable");
  // No redirection bitmap: the card is composed with per-pixel alpha, which is
  // what gives it rounded corners instead of a rectangular window cut-out.
  window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST |
                                WS_EX_NOREDIRECTIONBITMAP,
                            class_name, L"", WS_POPUP, 0, 0, 1, 1, nullptr,
                            nullptr, descriptor.hInstance, this);
  if (!window_)
    throw std::runtime_error("Candidate window unavailable");
}
CandidateWindow::Apartment::Apartment() {
  const HRESULT entered =
      CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  // S_FALSE only means this thread was already inside the same apartment; the
  // reference still has to be released. A different mode is left untouched.
  if (FAILED(entered) && entered != RPC_E_CHANGED_MODE)
    throw std::runtime_error("Candidate apartment unavailable");
  owned = entered != RPC_E_CHANGED_MODE;
}
CandidateWindow::Apartment::~Apartment() {
  if (owned)
    CoUninitialize();
}
CandidateWindow::~CandidateWindow() {
  if (window_)
    DestroyWindow(window_);
}
void CandidateWindow::set_palette(CandidatePalette palette) {
  palette_ = std::move(palette);
  painted_.reset();
  if (window_)
    InvalidateRect(window_, nullptr, FALSE);
}
void CandidateWindow::hide() {
  shown_.reset();
  painted_.reset();
  pressed_.reset();
  hovered_.reset();
  wheel_accumulator_ = 0;
  ShowWindow(window_, SW_HIDE);
}
// Measuring the page reads Engine text, so unusable presentation data reaches
// this path as well as the paint one. The owner's thread learns nothing about
// it: the card gives up and stays hidden, exactly as the window procedure does.
void CandidateWindow::refresh() {
  DpiScope dpi_scope;
  if (failed_) {
    hide();
    return;
  }
  try {
    reposition();
  } catch (...) {
    failed_ = true;
    hide();
  }
}
void CandidateWindow::reposition() {
  const auto value = reader_();
  if (!value || !value->visible) {
    hide();
    return;
  }
  // The first show can arrive before TSF has produced a usable text extent.
  // Do not let card_bounds clamp the sentinel into the monitor work area; a
  // subsequent MoveCandidateWnd with a real anchor will retry this refresh.
  if (value->y == invalid_candidate_anchor_y) {
    hide();
    return;
  }
  if (value->candidates.size() > 9)
    throw std::invalid_argument("Oversized window page");
  if (shown_ && shown_dpi_ == GetDpiForWindow(window_) &&
      shown_->session == value->session &&
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
  // Move a hidden one-pixel window onto the target monitor first. Its own DPI,
  // rather than process-global or previous-monitor DPI, determines the layout.
  if (MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST) !=
      MonitorFromPoint({value->x, value->y}, MONITOR_DEFAULTTONEAREST)) {
    hide();
    if (!SetWindowPos(window_, nullptr, work.left, work.top, 1, 1,
                      SWP_NOACTIVATE | SWP_NOZORDER))
      throw std::runtime_error("Candidate monitor move failed");
  }
  const auto dpi = GetDpiForWindow(window_);
  const auto bounds = card_bounds(*value, work, dpi);
  if (!SetWindowPos(window_, HWND_TOPMOST, bounds.x, bounds.y, bounds.width,
                    bounds.height, SWP_NOACTIVATE | SWP_SHOWWINDOW))
    throw std::runtime_error("Candidate positioning failed");
  shown_ = value;
  shown_dpi_ = dpi;
  InvalidateRect(window_, nullptr, FALSE);
}
// Measure the page, size the card from the shared geometry and keep it inside
// the work area. Half the work area caps each axis, as the shipped card does.
CandidateBounds CandidateWindow::card_bounds(const CandidatePresentation &value,
                                             const RECT &work, unsigned dpi) {
  const int64_t available_width = int64_t(work.right) - work.left;
  const int64_t available_height = int64_t(work.bottom) - work.top;
  if (available_width <= 0 || available_height <= 0)
    throw std::invalid_argument("Invalid candidate work area");
  device_.EnsureFactories();
  const double scale = static_cast<double>(dpi) / 96.0;
  CandidateCardInput input;
  input.horizontal = horizontal_;
  input.preedit_visible = show_preedit_;
  input.font_size = font_size_;
  input.preedit_font_size = preedit_font_size_;
  input.max_width = static_cast<double>(available_width) / scale / 2.0;
  input.max_height = static_cast<double>(available_height) / scale / 2.0;
  if (show_preedit_)
    input.preedit_width = measured_width(device_, wide(value.preedit),
                                         font_family_,
                                         static_cast<float>(preedit_font_size_));
  for (const auto &candidate : value.candidates) {
    auto label = candidate.text + candidate.annotation + candidate.badge;
    if (!candidate.translation.empty())
      label += "  · " + candidate.translation;
    input.item_widths.push_back(measured_width(
        device_, wide(label), font_family_, static_cast<float>(font_size_)));
  }
  const auto card = candidate_card_size(input);
  const auto width =
      (std::min)(static_cast<int64_t>(card.width * scale + 0.5), available_width);
  const auto height =
      (std::min)(static_cast<int64_t>(card.height * scale + 0.5), available_height);
  return {static_cast<int>((std::clamp)(int64_t(value.x), int64_t(work.left),
                                        int64_t(work.right) - width)),
          static_cast<int>((std::clamp)(int64_t(value.y), int64_t(work.top),
                                        int64_t(work.bottom) - height)),
          static_cast<int>(width), static_cast<int>(height)};
}
void CandidateWindow::paint() {
  DpiScope dpi_scope;
  Painting painting(window_);
  if (!painting.dc)
    throw std::runtime_error("Candidate painting unavailable");
  const auto value = reader_(); // Never paint the last cached owner's text.
  if (!value || !value->visible) {
    hide();
    return;
  }
  if (value->candidates.size() > 9)
    throw std::invalid_argument("Oversized window page");
  if (!device_.EnsureForComposition(window_))
    throw std::runtime_error("Candidate device unavailable");
  auto *target = device_.GetRenderTarget();
  if (!target)
    throw std::runtime_error("Candidate render target unavailable");
  // DrawText goes through the windows.h macro so the call matches whichever
  // name the Direct2D declaration picked up for this target.
  const auto metrics = candidate_card_metrics(font_size_, preedit_font_size_,
                                              show_preedit_);
  const auto size = target->GetSize();
  auto brush = [&](const CandidateColor &color) {
    auto *value = device_.GetSolidColorBrush(D2D1::ColorF(color.r, color.g, color.b, color.a));
    if (!value)
      throw std::runtime_error("Candidate brush unavailable");
    return value;
  };
  // Points are device independent here; the composition target carries the
  // scale, so the constructor's validated sizes go straight to DirectWrite.
  auto format = [&](unsigned points, DWRITE_TEXT_ALIGNMENT alignment) {
    auto *value = device_.GetTextFormat(
        font_family_, static_cast<float>(points),
        DWRITE_FONT_WEIGHT_NORMAL, alignment, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
        DWRITE_WORD_WRAPPING_NO_WRAP);
    if (!value)
      throw std::runtime_error("Candidate text format unavailable");
    return value;
  };
  const float inset = palette_.border_width / 2.0f;
  // The configured text color still wins over the skin token.
  const CandidateColor text_color =
      text_color_ ? candidate_rgb(GetRValue(*text_color_) << 16 |
                                  GetGValue(*text_color_) << 8 |
                                  GetBValue(*text_color_))
                  : palette_.text;
  target->BeginDraw();
  // Clear to nothing: only the rounded card itself is opaque, so the corners
  // stay transparent rather than showing a square window edge.
  target->Clear(D2D1::ColorF(0.0f, 0.0f, 0.0f, 0.0f));
  const D2D1_ROUNDED_RECT card{
      {inset, inset, size.width - inset, size.height - inset},
      palette_.radius, palette_.radius};
  target->FillRoundedRectangle(card, brush(palette_.surface));
  target->DrawRoundedRectangle(card, brush(palette_.border),
                               palette_.border_width);
  if (show_preedit_) {
    const D2D1_RECT_F rect{static_cast<float>(metrics.pad_x),
                           static_cast<float>(metrics.pad_y),
                           size.width - static_cast<float>(metrics.pad_x / 2.0),
                           static_cast<float>(metrics.pad_y + metrics.preedit_row)};
    const auto text = wide(value->preedit);
    target->DrawText(text.c_str(), static_cast<UINT32>(text.size()),
                      format(preedit_font_size_, DWRITE_TEXT_ALIGNMENT_LEADING),
                      rect, brush(text_color));
  }
  // The selection number keeps its own column so candidates start on one
  // vertical line, as the shipped card does.
  const float number = static_cast<float>(font_size_) * 0.8f;
  const float gutter = static_cast<float>(metrics.number_and_bar);
  const size_t count = value->candidates.size();
  for (size_t i = 0; i < count; ++i) {
    const auto row = candidate_row_bounds(i, count, size.width, metrics,
                                          horizontal_);
    const D2D1_RECT_F rect{
        static_cast<float>(row.left), static_cast<float>(row.top),
        static_cast<float>(row.right), static_cast<float>(row.bottom)};
    if (value->candidates[i].highlighted || hovered_ == i) {
      const D2D1_ROUNDED_RECT selection{rect, palette_.item_radius,
                                        palette_.item_radius};
      target->FillRoundedRectangle(selection, brush(value->candidates[i].highlighted
                                                        ? palette_.selected
                                                        : palette_.hover));
      if (value->candidates[i].highlighted && palette_.show_selected_bar) {
        const float inset_y =
            static_cast<float>(metrics.candidate_row) * 0.25f;
        const D2D1_ROUNDED_RECT bar{{rect.left + 2.0f, rect.top + inset_y,
                                     rect.left + 5.0f, rect.bottom - inset_y},
                                    1.5f, 1.5f};
        target->FillRoundedRectangle(bar, brush(palette_.accent));
      }
    }
    // Alpha 0 means the skin named no selected colour, so the row keeps its
    // normal one. Skins that fill the selection with an opaque accent set it,
    // because their unselected text would otherwise be unreadable on the fill.
    const bool selected = value->candidates[i].highlighted;
    const auto number_color =
        selected && palette_.selected_number.a > 0.0f ? palette_.selected_number
                                                      : palette_.number;
    const auto row_text_color =
        selected && palette_.selected_text.a > 0.0f ? palette_.selected_text
                                                    : text_color;
    const auto label = std::to_wstring(i + 1);
    target->DrawText(label.c_str(), static_cast<UINT32>(label.size()),
                      format(font_size_, DWRITE_TEXT_ALIGNMENT_TRAILING),
                      D2D1_RECT_F{rect.left, rect.top, rect.left + number,
                                  rect.bottom},
                      brush(number_color));
    auto candidate_label = value->candidates[i].text +
                           value->candidates[i].annotation +
                           value->candidates[i].badge;
    if (!value->candidates[i].translation.empty())
      candidate_label += "  · " + value->candidates[i].translation;
    const auto text = wide(candidate_label);
    target->DrawText(text.c_str(), static_cast<UINT32>(text.size()),
                      format(font_size_, DWRITE_TEXT_ALIGNMENT_LEADING),
                      D2D1_RECT_F{rect.left + gutter, rect.top, rect.right,
                                  rect.bottom},
                      brush(value->candidates[i].fixed_position
                                ? palette_.accent
                                : row_text_color));
  }
  const HRESULT drawn = target->EndDraw();
  // A composition swap chain only reaches the screen once it is presented.
  if (SUCCEEDED(drawn) && FAILED(device_.Present()))
    throw std::runtime_error("Candidate presentation failed");
  if (drawn == D2DERR_RECREATE_TARGET) {
    // Losing the device is not a presentation failure; rebuild on the next
    // refresh rather than hiding a live composition. Clearing shown_ is what
    // makes that rebuild reachable: reposition() returns early while the cached
    // frame still matches, so leaving it set would suppress the very repaint
    // this path is counting on, and painted_ would stay behind for good. That
    // also strands clicks, because hit() refuses without a painted page.
    device_.DiscardTarget();
    shown_.reset();
    InvalidateRect(window_, nullptr, FALSE);
    return;
  }
  if (FAILED(drawn))
    throw std::runtime_error("Candidate drawing failed");
  painted_ = value;
  painted_dpi_ = GetDpiForWindow(window_);
}
std::optional<CandidateClick> CandidateWindow::hit(int x, int y) {
  if (!click_ || !painted_ || !IsWindowVisible(window_))
    return std::nullopt;
  RECT bounds{};
  if (!GetClientRect(window_, &bounds))
    return std::nullopt;
  const double scale = painted_dpi_ ? painted_dpi_ / 96.0 : 1.0;
  const auto row = candidate_card_hit(
      x / scale, y / scale, bounds.right / scale, bounds.bottom / scale,
      painted_->candidates.size(),
      candidate_card_metrics(font_size_, preedit_font_size_, show_preedit_),
      horizontal_);
  if (!row)
    return std::nullopt;
  const auto &candidate = painted_->candidates[*row];
  return CandidateClick{painted_->lease, candidate.session,
                        candidate.generation, candidate.index};
}
void CandidateWindow::show_context_menu(const CandidateClick &click,
                                        POINT client_point) {
  if (!painted_ || !click_)
    return;
  const auto candidate = std::find_if(
      painted_->candidates.begin(), painted_->candidates.end(),
      [&](const PresentationCandidate &item) {
        return item.session == click.session &&
               item.generation == click.generation &&
               item.index == click.index;
      });
  if (candidate == painted_->candidates.end())
    return;
  const auto text = wide(candidate->text);
  size_t code_points = 0;
  for (size_t i = 0; i < text.size(); ++i) {
    ++code_points;
    if (i + 1 < text.size() &&
        IS_HIGH_SURROGATE(text[i]) && IS_LOW_SURROGATE(text[i + 1]))
      ++i;
  }

  PopupMenu menu(CreatePopupMenu());
  if (!menu.handle)
    throw std::runtime_error("Candidate context menu unavailable");
  append_menu(menu.handle, MF_STRING, menu_pin, L"置顶");
  PopupMenu fixed(CreatePopupMenu());
  if (!fixed.handle)
    throw std::runtime_error("Candidate context menu unavailable");
  for (UINT position = 1; position <= 5; ++position)
    append_menu(fixed.handle, MF_STRING, menu_fix_first + position - 1,
                (L"第 " + std::to_wstring(position) + L" 位").c_str());
  append_menu(fixed.handle, MF_SEPARATOR, 0, nullptr);
  append_menu(fixed.handle, MF_STRING, menu_clear_fix, L"取消固定");
  append_menu(menu.handle, MF_POPUP,
              reinterpret_cast<UINT_PTR>(fixed.handle), L"固定排位");
  fixed.handle = nullptr; // Ownership now belongs to the parent menu.
  if (code_points != 1)
    append_menu(menu.handle, MF_STRING, menu_remove, L"删除");

  POINT screen = client_point;
  if (!ClientToScreen(window_, &screen))
    throw std::runtime_error("Candidate context menu position unavailable");
  const UINT command = TrackPopupMenuEx(
      menu.handle, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NOANIMATION,
      screen.x, screen.y, window_, nullptr);
  CandidateClick action = click;
  if (command == menu_pin)
    action.action = CandidateAction::Pin;
  else if (command == menu_remove && code_points != 1)
    action.action = CandidateAction::Remove;
  else if (command >= menu_fix_first && command <= menu_fix_last) {
    action.action = CandidateAction::FixPosition;
    action.position = static_cast<uint8_t>(command - menu_fix_first + 1);
  } else if (command == menu_clear_fix) {
    action.action = CandidateAction::ClearPosition;
  } else {
    return;
  }
  click_(action);
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
        return self->click_ ? MA_NOACTIVATE : MA_NOACTIVATEANDEAT;
      case WM_MOUSEWHEEL: {
        if (!self->page_ || !self->painted_ || !IsWindowVisible(window)) {
          self->wheel_accumulator_ = 0;
          return 0;
        }
        const auto steps = consume_candidate_wheel_delta(
            self->wheel_accumulator_, GET_WHEEL_DELTA_WPARAM(wparam),
            WHEEL_DELTA);
        const auto &value = *self->painted_;
        if (steps.page_up > 0)
          self->page_(CandidatePage{value.lease, value.session, value.generation,
                                    true, static_cast<unsigned>(steps.page_up)});
        if (steps.page_down > 0)
          self->page_(CandidatePage{value.lease, value.session, value.generation,
                                    false, static_cast<unsigned>(steps.page_down)});
        return 0;
      }
      case WM_LBUTTONDOWN:
        self->pressed_ = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        if (self->pressed_) {
          SetCapture(window);
          TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
          if (!TrackMouseEvent(&track))
            self->pressed_.reset();
        }
        return 0;
      case WM_MOUSEMOVE: {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
        TrackMouseEvent(&track);
        const auto click = self->hit(static_cast<short>(LOWORD(lparam)),
                                     static_cast<short>(HIWORD(lparam)));
        SetCursor(LoadCursorW(nullptr, click ? wide_cursor(IDC_HAND)
                                             : wide_cursor(IDC_ARROW)));
        std::optional<size_t> hovered;
        if (click && self->painted_) {
          for (size_t i = 0; i < self->painted_->candidates.size(); ++i)
            if (self->painted_->candidates[i].index == click->index) hovered = i;
        }
        if (hovered != self->hovered_) { self->hovered_ = hovered; InvalidateRect(window, nullptr, FALSE); }
        return 0;
      }
      case WM_LBUTTONUP: {
        if (GetCapture() == window) ReleaseCapture();
        const auto pressed = self->pressed_;
        self->pressed_.reset();
        const auto hit = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        if (pressed && hit && pressed->session == hit->session &&
            pressed->generation == hit->generation &&
            pressed->index == hit->index &&
            pressed->lease.epoch == hit->lease.epoch &&
            pressed->lease.token == hit->lease.token &&
            same_ticket(pressed->lease.transport, hit->lease.transport))
          self->click_(*hit);
        return 0;
      }
      case WM_RBUTTONUP: {
        const auto hit = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        if (hit)
          self->show_context_menu(*hit,
                                  POINT{static_cast<short>(LOWORD(lparam)),
                                        static_cast<short>(HIWORD(lparam))});
        return 0;
      }
      case WM_CANCELMODE:
      case WM_CAPTURECHANGED:
      case WM_MOUSELEAVE:
        if (GetCapture() == window) ReleaseCapture();
        self->pressed_.reset();
        self->hovered_.reset();
        SetCursor(LoadCursorW(nullptr, wide_cursor(IDC_ARROW)));
        return 0;
      case WM_ERASEBKGND:
        return 1;
      case WM_DISPLAYCHANGE:
      case WM_SETTINGCHANGE:
      case WM_DPICHANGED:
        // The next refresh recomputes from the authenticated caret anchor;
        // do not recursively reposition from inside SetWindowPos's callback.
        self->shown_.reset();
        self->painted_.reset();
        self->pressed_.reset();
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

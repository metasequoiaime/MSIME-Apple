#include "CandidateWindow.h"
#include "CandidateLayout.h"
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
struct Painting {
  HWND window;
  PAINTSTRUCT state{};
  HDC dc;
  explicit Painting(HWND value)
      : window(value), dc(BeginPaint(window, &state)) {}
  ~Painting() { EndPaint(window, &state); }
};
} // namespace
CandidateWindow::CandidateWindow(Reader reader, Click click, unsigned font_size,
                                 unsigned preedit_font_size,
                                 std::optional<COLORREF> text_color,
                                 std::string font_family,
                                 std::vector<std::string> fallback_fonts,
                                 std::optional<bool> dark_theme,
                                 bool horizontal)
    : reader_(std::move(reader)), click_(std::move(click)), font_size_(font_size),
      preedit_font_size_(preedit_font_size), text_color_(text_color),
      font_family_(wide(font_family)), dark_theme_(dark_theme), horizontal_(horizontal) {
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
  painted_.reset();
  pressed_.reset();
  ShowWindow(window_, SW_HIDE);
}
void CandidateWindow::refresh() {
  DpiScope dpi_scope;
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
  const auto bounds =
      candidate_bounds(value->x, value->y, work.left, work.top, work.right,
      work.bottom, dpi, value->candidates.size(), font_size_, horizontal_);
  if (!SetWindowPos(window_, HWND_TOPMOST, bounds.x, bounds.y, bounds.width,
                    bounds.height, SWP_NOACTIVATE | SWP_SHOWWINDOW))
    throw std::runtime_error("Candidate positioning failed");
  shown_ = value;
  shown_dpi_ = dpi;
  InvalidateRect(window_, nullptr, FALSE);
}
void CandidateWindow::paint() {
  DpiScope dpi_scope;
  Painting painting(window_);
  if (!painting.dc)
    throw std::runtime_error("Candidate painting unavailable");
  RECT bounds{};
  GetClientRect(window_, &bounds);
  const auto background = dark_theme_.value_or(false) ? RGB(32, 32, 32) : GetSysColor(COLOR_WINDOW);
  const auto foreground = dark_theme_.value_or(false) ? RGB(243, 243, 243) : GetSysColor(COLOR_WINDOWTEXT);
  const auto highlight = dark_theme_.value_or(false) ? RGB(76, 74, 150) : GetSysColor(COLOR_HIGHLIGHT);
  const auto highlight_text = dark_theme_.value_or(false) ? RGB(255, 255, 255) : GetSysColor(COLOR_HIGHLIGHTTEXT);
  HBRUSH background_brush = CreateSolidBrush(background);
  if (!background_brush) throw std::runtime_error("Candidate background unavailable");
  FillRect(painting.dc, &bounds, background_brush);
  DeleteObject(background_brush);
  const auto value = reader_(); // Never paint the last cached owner's text.
  if (!value || !value->visible) {
    hide();
    return;
  }
  if (value->candidates.size() > 9)
    throw std::invalid_argument("Oversized window page");
  const auto metrics = candidate_metrics(GetDpiForWindow(window_), font_size_);
  SetBkMode(painting.dc, TRANSPARENT);
  auto line = [&](const std::wstring &text, size_t row, bool highlighted) {
    RECT rect{metrics.padding,
              static_cast<LONG>(metrics.padding + row * metrics.row),
              bounds.right - metrics.padding,
              static_cast<LONG>(metrics.padding + (row + 1) * metrics.row)};
    if (highlighted) {
      HBRUSH brush = CreateSolidBrush(highlight);
      if (!brush) throw std::runtime_error("Candidate highlight unavailable");
      FillRect(painting.dc, &rect, brush);
      DeleteObject(brush);
    }
    SetTextColor(painting.dc, highlighted ? highlight_text : text_color_.value_or(foreground));
    rect.left += metrics.padding;
    DrawTextW(painting.dc, text.c_str(), static_cast<int>(text.size()), &rect,
              DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  };
  {
    Font preedit_font(painting.dc, candidate_metrics(
        GetDpiForWindow(window_), preedit_font_size_).font, font_family_.c_str());
    line(wide(value->preedit), 0, false);
  }
  {
    Font candidate_font(painting.dc, metrics.font, font_family_.c_str());
    for (size_t i = 0; i < value->candidates.size(); ++i)
      line(std::to_wstring(i + 1) + L". " + wide(value->candidates[i].text),
           horizontal_ ? 1 : i + 1, value->candidates[i].highlighted);
  }
  painted_ = value;
  painted_dpi_ = GetDpiForWindow(window_);
}
std::optional<CandidateClick> CandidateWindow::hit(int x, int y) {
  if (!click_ || !painted_ || !IsWindowVisible(window_))
    return std::nullopt;
  RECT bounds{};
  if (!GetClientRect(window_, &bounds))
    return std::nullopt;
  const auto row = candidate_hit(x, y, bounds.right, bounds.bottom,
                                 painted_dpi_, painted_->candidates.size(),
                                 font_size_, horizontal_);
  if (!row)
    return std::nullopt;
  const auto &candidate = painted_->candidates[*row];
  return CandidateClick{painted_->lease, candidate.session,
                        candidate.generation, candidate.index};
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
      case WM_LBUTTONDOWN:
        self->pressed_ = self->hit(static_cast<short>(LOWORD(lparam)),
                                   static_cast<short>(HIWORD(lparam)));
        if (self->pressed_) {
          TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE, window, 0};
          if (!TrackMouseEvent(&track))
            self->pressed_.reset();
        }
        return 0;
      case WM_LBUTTONUP: {
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
      case WM_CANCELMODE:
      case WM_CAPTURECHANGED:
      case WM_MOUSELEAVE:
        self->pressed_.reset();
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

#include "CandidateWindow.h"
#include "CandidateFlyoutWindow.h"
#include "CandidateFontFormat.h"
#include "CandidateWheel.h"
#include "CursorResource.h"
#include "NativeFontAlias.h"
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
                      const std::wstring &family, float size,
                      IDWriteFontFallback *fallback) {
  if (text.empty() || size <= 0.0f)
    return 0.0;
  auto *factory = device.GetDWriteFactory();
  auto *format = device.GetTextFormat(
      family, size, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_LEADING,
      DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_WORD_WRAPPING_NO_WRAP);
  set_candidate_font_fallback(format, fallback);
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
// Build a real per-glyph fallback chain from the configured faces.
//
// PreviewConfig documents these as "supplementary faces tried in order when the
// main font lacks a glyph", but the window only ever used them to replace the
// primary family when that family was not installed at all. Once the primary
// existed, a missing glyph fell through to DirectWrite's system fallback and
// the user's list was ignored entirely - which is the case the setting is for,
// since the primary is usually a Latin/CJK face and the missing glyph is an
// emoji or a rare character.
Microsoft::WRL::ComPtr<IDWriteFontFallback>
build_font_fallback(IDWriteFactory *factory,
                    const std::vector<std::wstring> &families) {
  Microsoft::WRL::ComPtr<IDWriteFontFallback> result;
  if (!factory || families.empty())
    return result;
  Microsoft::WRL::ComPtr<IDWriteFactory2> factory2;
  if (FAILED(factory->QueryInterface(IID_PPV_ARGS(&factory2))) || !factory2)
    return result; // Windows 7 and older: keep the system chain.
  Microsoft::WRL::ComPtr<IDWriteFontFallbackBuilder> builder;
  if (FAILED(factory2->CreateFontFallbackBuilder(&builder)) || !builder)
    return result;
  // The whole Unicode range, in the user's order.
  DWRITE_UNICODE_RANGE range{0, 0x10FFFF};
  for (const auto &family : families) {
    const wchar_t *name = family.c_str();
    if (FAILED(builder->AddMapping(&range, 1, &name, 1)))
      return result;
  }
  // Append the system chain last so anything the list does not cover still
  // resolves the way it did before.
  Microsoft::WRL::ComPtr<IDWriteFontFallback> system;
  if (SUCCEEDED(factory2->GetSystemFontFallback(&system)) && system)
    builder->AddMappings(system.Get());
  if (FAILED(builder->CreateFontFallback(&result)))
    result.Reset();
  return result;
}
// Owner-drawn menu rows.
//
// The rows and their rules were already right; only the presentation was the
// OS default, so a light system menu appeared over a dark card and no skin's
// colours reached it. Owner drawing keeps the platform's own keyboard handling
// and dismissal - which a hand-rolled flyout would have to reimplement - while
// painting the rows from the skin.
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
  // Keep the configured faces for the per-glyph chain, and separately allow one
  // of them to stand in when the primary family is not installed at all. The
  // two are different problems and both need handling.
  for (const auto &fallback : fallback_fonts) {
    auto candidate = wide(fallback);
    if (!candidate.empty() && candidate.size() <= 128)
      fallback_families_.push_back(std::move(candidate));
  }
  if (!installed_font(font_family_)) {
    for (const auto &candidate : fallback_families_) {
      if (installed_font(candidate)) {
        font_family_ = candidate;
        break;
      }
    }
  }
  // GDI selects installed faces above; DirectWrite needs canonical families
  // both for measurement and the per-glyph fallback mapping.
  font_family_ = native_font_alias(font_family_);
  for (auto &family : fallback_families_)
    family = native_font_alias(family);
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
void CandidateWindow::set_theme_palette(CandidatePalette palette) {
  // The freshly resolved palette contains the current text override. Do not
  // let the constructor's old COLORREF mask it after changing or clearing it.
  text_color_.reset();
  set_palette(std::move(palette));
  invalidate_geometry();
}
void CandidateWindow::invalidate_skin_images() {
  device_.ClearBitmapCache();
  invalidate_geometry();
}
bool CandidateWindow::set_fonts(const CandidateFontSettings &settings) {
  if (!settings.valid())
    return false;
  if (font_settings_ && *font_settings_ == settings)
    return true;
  try {
    // Resolve all names before replacing any live display state.
    auto primary = wide(settings.family);
    std::vector<std::wstring> fallback;
    for (const auto &name : settings.fallback)
      fallback.push_back(wide(name));
    if (!installed_font(primary)) {
      for (const auto &name : fallback) {
        if (installed_font(name)) {
          primary = name;
          break;
        }
      }
    }
    primary = native_font_alias(primary);
    for (auto &name : fallback)
      name = native_font_alias(name);
    auto remembered = settings;
    font_family_.swap(primary);
    fallback_families_.swap(fallback);
    font_settings_ = std::move(remembered);
    font_size_ = settings.size;
    preedit_font_size_ = settings.preedit_size;
    font_fallback_.Reset();
    invalidate_geometry();
    return true;
  } catch (...) {
    return false;
  }
}
void CandidateWindow::set_layout(CandidateLayoutSettings settings) {
  if (horizontal_ == settings.horizontal && show_preedit_ == settings.show_preedit)
    return;
  horizontal_ = settings.horizontal;
  show_preedit_ = settings.show_preedit;
  invalidate_geometry();
}
void CandidateWindow::invalidate_geometry() {
  // Geometry can change without an Engine generation change. Never reuse old
  // hit rectangles or a pressed row; keep the input lease and pinned anchor.
  shown_.reset();
  painted_.reset();
  pressed_.reset();
  hovered_.reset();
  wheel_accumulator_ = 0;
  tallest_ = 0;
  if (window_)
    InvalidateRect(window_, nullptr, FALSE);
}
void CandidateWindow::hide() {
  // The composition is over, so the next one starts its flip decision fresh.
  tallest_ = 0;
  // And its position fresh: "keep the first position" lasts until the card
  // disappears, so the next appearance anchors at the caret again.
  anchor_.reset();
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
  auto value = reader_();
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
  // 候选窗口跟随光标. With following off the card stays where it first
  // appeared: the caret still moves as the user types, but the anchor this
  // layout uses does not. Everything downstream - the monitor it lands on, the
  // flip decision, the cached-frame comparison below - reads the anchored
  // copy, so a caret move alone no longer even wakes the window.
  auto anchored = *value;
  if (!follow_cursor_) {
    if (anchor_) {
      anchored.x = anchor_->x;
      anchored.y = anchor_->y;
    } else {
      anchor_ = POINT{value->x, value->y};
    }
  }
  value = anchored;
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
  // The first layout precedes painting: do not let the format cache make font
  // selection depend on whether a previous frame has already been drawn.
  if (!fallback_families_.empty() && !font_fallback_)
    font_fallback_ = build_font_fallback(device_.GetDWriteFactory(),
                                        fallback_families_);
  const double scale = static_cast<double>(dpi) / 96.0;
  CandidateCardInput input;
  input.horizontal = horizontal_;
  input.preedit_visible = show_preedit_;
  input.font_size = font_size_;
  input.preedit_font_size = preedit_font_size_;
  input.max_width = static_cast<double>(available_width) / scale / 2.0;
  input.max_height = static_cast<double>(available_height) / scale / 2.0;
  input.skin_min_width = skin_min_width_;
  if (show_preedit_)
    input.preedit_width = measured_width(device_, wide(value.preedit),
                                         font_family_,
                                         static_cast<float>(preedit_font_size_),
                                         font_fallback_.Get());
  for (const auto &candidate : value.candidates) {
    auto label = candidate.text + candidate.annotation + candidate.badge;
    if (!candidate.translation.empty())
      label += "  · " + candidate.translation;
    input.item_widths.push_back(measured_width(
        device_, wide(label), font_family_, static_cast<float>(font_size_),
        font_fallback_.Get()));
  }
  const auto card = candidate_card_size(input);
  const auto width =
      (std::min)(static_cast<int64_t>(card.width * scale + 0.5), available_width);
  // The window has to be tall enough to hold the mascot as well, or the
  // artwork would be clipped by the window it overhangs.
  const int64_t decoration = decoration_image_.empty()
                                 ? 0
                                 : static_cast<int64_t>(decoration_top_ * scale + 0.5);
  decoration_offset_ = static_cast<float>(decoration);
  const auto height = (std::min)(
      static_cast<int64_t>(card.height * scale + 0.5) + decoration,
      available_height);
  // A vertical list grows as the user keeps typing. Deciding the flip from the
  // tallest it has been this composition keeps it on one side of the caret
  // instead of jumping below-to-above mid-word; tallest_ is cleared in hide().
  if (!horizontal_)
    tallest_ = (std::max)(tallest_, height);
  CandidatePlacementInput placement;
  placement.anchor_x = value.x;
  placement.anchor_y = value.y;
  placement.width = static_cast<int>(width);
  placement.height = static_cast<int>(height);
  placement.decision_height =
      static_cast<int>(horizontal_ ? height : (std::min)(tallest_, available_height));
  placement.work_left = work.left;
  placement.work_top = work.top;
  placement.work_right = work.right;
  placement.work_bottom = work.bottom;
  placement.scale = scale;
  const auto placed = candidate_card_placement(placement);
  return {placed.x, placed.y, static_cast<int>(width),
          static_cast<int>(height)};
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
  // Built once per paint and shared by every run below; the formats themselves
  // are cached by DeviceResources, so attaching here is what actually puts the
  // user's faces in front of the system chain.
  if (!fallback_families_.empty() && !font_fallback_)
    font_fallback_ = build_font_fallback(device_.GetDWriteFactory(),
                                         fallback_families_);
  auto format = [&](unsigned points, DWRITE_TEXT_ALIGNMENT alignment) {
    auto *value = device_.GetTextFormat(
        font_family_, static_cast<float>(points),
        DWRITE_FONT_WEIGHT_NORMAL, alignment, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
        DWRITE_WORD_WRAPPING_NO_WRAP);
    if (!value)
      throw std::runtime_error("Candidate text format unavailable");
    set_candidate_font_fallback(value, font_fallback_.Get());
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
      {inset, decoration_offset_ + inset, size.width - inset,
       size.height - inset},
      palette_.radius, palette_.radius};
  target->FillRoundedRectangle(card, brush(palette_.surface));
  target->DrawRoundedRectangle(card, brush(palette_.border),
                               palette_.border_width);
  // The mascot, drawn last so it sits over the card's top edge - that overlap
  // is the whole point of the decoration.
  if (!decoration_image_.empty() && decoration_offset_ > 0.0f) {
    D2D1_SIZE_F natural{};
    if (auto *bitmap = device_.GetBitmapFromFile(decoration_image_, &natural)) {
      const float drawn_width = static_cast<float>(decoration_width_);
      // Keep the image's own aspect ratio: a package gives a width, not a box,
      // so deriving the height is what stops the artwork being squashed.
      const float drawn_height =
          natural.width > 0.0f ? drawn_width * (natural.height / natural.width)
                               : decoration_offset_;
      // Right-aligned above the card, as the settings preview places it.
      const float right = size.width - static_cast<float>(metrics.pad_x);
      const float left = (std::max)(0.0f, right - drawn_width);
      const float bottom = decoration_offset_ + static_cast<float>(metrics.pad_y);
      const float top = (std::max)(0.0f, bottom - drawn_height);
      target->DrawBitmap(bitmap, D2D1_RECT_F{left, top, right, bottom}, 1.0f,
                         D2D1_BITMAP_INTERPOLATION_MODE_LINEAR);
    }
  }
  if (show_preedit_) {
    const D2D1_RECT_F rect{
        static_cast<float>(metrics.pad_x),
        decoration_offset_ + static_cast<float>(metrics.pad_y),
        size.width - static_cast<float>(metrics.pad_x / 2.0),
        decoration_offset_ +
            static_cast<float>(metrics.pad_y + metrics.preedit_row)};
    const auto text = wide(value->preedit);
    target->DrawText(text.c_str(), static_cast<UINT32>(text.size()),
                      format(preedit_font_size_, DWRITE_TEXT_ALIGNMENT_LEADING),
                      rect, brush(text_color));
    // The insertion point. Without it, moving left or right inside a long
    // pinyin string gave no indication of where the next key would land - and
    // the settings preview drew a caret the real window never did.
    if (value->preedit_caret != std::string::npos &&
        value->preedit_caret <= value->preedit.size()) {
      const auto before =
          wide(value->preedit.substr(0, value->preedit_caret));
      const auto offset = measured_width(
          device_, before, font_family_,
          static_cast<float>(preedit_font_size_), font_fallback_.Get());
      const float x = rect.left + static_cast<float>(offset);
      // A hairline rather than a filled block, so it does not obscure the
      // character it sits before.
      const float inset_y = static_cast<float>(metrics.preedit_row) * 0.15f;
      target->FillRectangle(
          D2D1_RECT_F{x, rect.top + inset_y, x + 1.5f, rect.bottom - inset_y},
          brush(palette_.accent));
    }
  }
  // The selection number keeps its own column so candidates start on one
  // vertical line, as the shipped card does.
  const float number = static_cast<float>(font_size_) * 0.8f;
  const float gutter = static_cast<float>(metrics.number_and_bar);
  const size_t count = value->candidates.size();
  for (size_t i = 0; i < count; ++i) {
    const auto row = candidate_row_bounds(i, count, size.width, metrics,
                                          horizontal_);
    // Rows are laid out in card coordinates; the decoration strip sits above
    // the card, so every row moves down with it. Without this the rows would
    // be drawn over the artwork and the hit test below would disagree.
    const D2D1_RECT_F rect{
        static_cast<float>(row.left), decoration_offset_ + static_cast<float>(row.top),
        static_cast<float>(row.right),
        decoration_offset_ + static_cast<float>(row.bottom)};
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
        candidate_row_text_color(palette_, text_color, selected,
                                 value->candidates[i].fixed_position != 0);
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
    target->DrawText(
        text.c_str(), static_cast<UINT32>(text.size()),
        format(font_size_, DWRITE_TEXT_ALIGNMENT_LEADING),
        D2D1_RECT_F{rect.left + gutter, rect.top, rect.right, rect.bottom},
        brush(row_text_color));
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
  // Undo the decoration shift before testing: the rows were drawn that far
  // down, so a click has to be measured from the card, not the window.
  const double card_y = y - static_cast<double>(decoration_offset_);
  if (card_y < 0.0)
    return std::nullopt; // Inside the artwork, which is not clickable.
  const auto row = candidate_card_hit(
      x / scale, card_y / scale, bounds.right / scale,
      (bounds.bottom - static_cast<double>(decoration_offset_)) / scale,
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

  // The flyout is not modal. TrackPopupMenuEx ran a nested message loop, and
  // the Server's pump is a bounded PeekMessage batch that also applies
  // preference changes, syncs Caps Lock and drives the toolbar - so for as
  // long as the menu was open, none of that ran.
  if (!flyout_) {
    flyout_ = std::make_unique<CandidateFlyoutWindow>(
        [this, click](const CandidateMenuChoice &choice) {
          if (!click_)
            return;
          CandidateClick action = click;
          switch (choice.command) {
          case CandidateMenuCommand::PinToTop:
            action.action = CandidateAction::Pin;
            break;
          case CandidateMenuCommand::Remove:
            action.action = CandidateAction::Remove;
            break;
          case CandidateMenuCommand::FixAtPosition:
            action.action = CandidateAction::FixPosition;
            action.position = static_cast<uint8_t>(choice.position);
            break;
          case CandidateMenuCommand::ClearFixedPosition:
            action.action = CandidateAction::ClearPosition;
            break;
          case CandidateMenuCommand::FixPosition:
            // Opens the submenu; never itself a chosen command.
            return;
          }
          click_(action);
        });
    flyout_->set_palette(palette_);
  }
  POINT screen = client_point;
  if (!ClientToScreen(window_, &screen))
    throw std::runtime_error("Candidate context menu position unavailable");
  flyout_->open(screen.x, screen.y, code_points);
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

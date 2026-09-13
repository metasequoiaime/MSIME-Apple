#pragma once
#include "CandidateCardSize.h"
#include "CandidateClickWorker.h"
#include "CandidatePalette.h"
#include "CandidatePresentation.h"
#include <functional>
// windows.h first: its DrawText macro has to reach the Direct2D declarations,
// which is how the rest of this UI stack spells DrawTextW.
#include <windows.h>
#include <msimeui/DeviceResources.h>

namespace msime::windows {
// Main/UI thread owns construction, polling, painting and destruction. Reader
// outlives the window and returns a freshly validated value, never Engine
// state.
class CandidateWindow final {
public:
  using Reader = std::function<std::optional<CandidatePresentation>()>;
  using Click = std::function<void(const CandidateClick &)>;
  explicit CandidateWindow(Reader reader, Click click = {}, unsigned font_size = 16,
                           unsigned preedit_font_size = 16,
                           std::optional<COLORREF> text_color = std::nullopt,
                           std::string font_family = "Segoe UI",
                           std::vector<std::string> fallback_fonts = {},
                           std::optional<bool> dark_theme = std::nullopt,
                           bool horizontal = false, bool show_preedit = true);
  ~CandidateWindow();
  CandidateWindow(const CandidateWindow &) = delete;
  CandidateWindow &operator=(const CandidateWindow &) = delete;
  void refresh();
  // Adopt resolved skin tokens. The next refresh repaints with them; the
  // built-in theme stays in place until a package is actually resolved.
  void set_palette(CandidatePalette palette);
  void hide();
  bool failed() const { return failed_; }
  HWND handle() const { return window_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void reposition();
  CandidateBounds card_bounds(const CandidatePresentation &value,
                              const RECT &work, unsigned dpi);
  void paint();
  std::optional<CandidateClick> hit(int x, int y);
  Reader reader_;
  Click click_;
  HWND window_ = nullptr;
  std::optional<CandidatePresentation> shown_;
  unsigned shown_dpi_ = 0;
  std::optional<CandidatePresentation> painted_;
  std::optional<CandidateClick> pressed_;
  std::optional<size_t> hovered_;
  unsigned painted_dpi_ = 0;
  bool failed_ = false;
  unsigned font_size_ = 16;
  unsigned preedit_font_size_ = 16;
  std::optional<COLORREF> text_color_;
  // Direct2D's imaging factory is a COM server, and this thread is the Server's
  // own UI thread, which otherwise never enters an apartment.
  struct Apartment {
    Apartment();
    ~Apartment();
    Apartment(const Apartment &) = delete;
    Apartment &operator=(const Apartment &) = delete;
    bool owned = false;
  } apartment_;
  // Direct2D through the shared UI stack; no second renderer in this tree.
  msimeui::DeviceResources device_;
  CandidatePalette palette_;
  std::wstring font_family_;
  std::optional<bool> dark_theme_;
  bool horizontal_ = false;
  bool show_preedit_ = true;
};
} // namespace msime::windows

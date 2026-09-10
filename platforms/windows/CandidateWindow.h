#pragma once
#include "CandidatePresentation.h"
#include "CandidateClickWorker.h"
#include <functional>
#include <windows.h>

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
                           std::optional<bool> dark_theme = std::nullopt);
  ~CandidateWindow();
  CandidateWindow(const CandidateWindow &) = delete;
  CandidateWindow &operator=(const CandidateWindow &) = delete;
  void refresh();
  void hide();
  bool failed() const { return failed_; }
  HWND handle() const { return window_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  std::optional<CandidateClick> hit(int x, int y);
  Reader reader_;
  Click click_;
  HWND window_ = nullptr;
  std::optional<CandidatePresentation> shown_;
  unsigned shown_dpi_ = 0;
  std::optional<CandidatePresentation> painted_;
  std::optional<CandidateClick> pressed_;
  unsigned painted_dpi_ = 0;
  bool failed_ = false;
  unsigned font_size_ = 16;
  unsigned preedit_font_size_ = 16;
  std::optional<COLORREF> text_color_;
  std::wstring font_family_;
  std::optional<bool> dark_theme_;
};
} // namespace msime::windows

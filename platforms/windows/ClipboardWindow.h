#pragma once
#include "ClipboardPresentation.h"
#ifdef _WIN32
#include <windows.h>
#include <functional>
namespace msime::windows {
class ClipboardWindow final {
public:
  using Reader = std::function<std::optional<ClipboardPresentation>()>;
  using Click = std::function<void(size_t)>;
  ClipboardWindow(Reader reader, Click click);
  ~ClipboardWindow();
  ClipboardWindow(const ClipboardWindow &) = delete;
  ClipboardWindow &operator=(const ClipboardWindow &) = delete;
  void refresh();
  void hide();
  bool failed() const { return failed_; }
private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  Reader reader_; Click click_; HWND window_ = nullptr;
  std::optional<ClipboardPresentation> shown_; bool failed_ = false;
};
} // namespace msime::windows
#endif

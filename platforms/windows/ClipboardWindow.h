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
  using Remove = std::function<void(size_t)>;
  using Clear = std::function<void()>;
  ClipboardWindow(Reader reader, Click click, Remove remove = {}, Clear clear = {});
  ~ClipboardWindow();
  ClipboardWindow(const ClipboardWindow &) = delete;
  ClipboardWindow &operator=(const ClipboardWindow &) = delete;
  void refresh();
  void hide();
  bool failed() const { return failed_; }
private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  Reader reader_; Click click_; Remove remove_; Clear clear_; HWND window_ = nullptr;
  std::optional<ClipboardPresentation> shown_; unsigned dpi_ = 96; bool failed_ = false;
};
} // namespace msime::windows
#endif

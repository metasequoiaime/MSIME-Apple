#pragma once
#include "ModeMailbox.h"
#include <functional>
#include <windows.h>

namespace msime::windows {
class FloatingToolbarWindow final {
public:
  using Reader = std::function<std::optional<ModePresentation>()>;
  explicit FloatingToolbarWindow(Reader reader);
  ~FloatingToolbarWindow();
  FloatingToolbarWindow(const FloatingToolbarWindow &) = delete;
  FloatingToolbarWindow &operator=(const FloatingToolbarWindow &) = delete;
  void refresh(bool enabled);
  void hide();
  bool failed() const { return failed_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  Reader reader_;
  HWND window_ = nullptr;
  std::optional<ModePresentation> shown_;
  bool failed_ = false;
};
} // namespace msime::windows

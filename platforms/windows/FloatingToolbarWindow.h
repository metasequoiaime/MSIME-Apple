#pragma once
#include "ModeWindow.h"
#include <functional>
#include <windows.h>

namespace msime::windows {
class FloatingToolbarWindow final {
public:
  using Reader = std::function<std::optional<ModePresentation>()>;
  using Click = std::function<void(const ModeClick &)>;
  FloatingToolbarWindow(Reader reader, Click click);
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
  Click click_;
  HWND window_ = nullptr;
  std::optional<ModePresentation> shown_;
  bool failed_ = false;
};
} // namespace msime::windows

#pragma once
#include "ModeWindow.h"
#include <functional>
// windows.h first: its DrawText macro has to reach the Direct2D declarations.
#include <windows.h>
#include <msimeui/DeviceResources.h>

namespace msime::windows {
class FloatingToolbarWindow final {
public:
  using Reader = std::function<std::optional<ModePresentation>()>;
  using Click = std::function<void(const ModeClick &)>;
  FloatingToolbarWindow(Reader reader, Click click);
  ~FloatingToolbarWindow();
  // Share the candidate card's resolved tokens so one theme covers the surface.
  void set_palette(CandidatePalette palette);
  FloatingToolbarWindow(const FloatingToolbarWindow &) = delete;
  FloatingToolbarWindow &operator=(const FloatingToolbarWindow &) = delete;
  void refresh(bool enabled);
  void hide();
  bool failed() const { return failed_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  // Direct2D's imaging factory is a COM server; this thread owns an apartment.
  struct Apartment {
    Apartment();
    ~Apartment();
    Apartment(const Apartment &) = delete;
    Apartment &operator=(const Apartment &) = delete;
    bool owned = false;
  } apartment_;
  msimeui::DeviceResources device_;
  CandidatePalette palette_;
  Reader reader_;
  Click click_;
  HWND window_ = nullptr;
  std::optional<ModePresentation> shown_;
  bool failed_ = false;
};
} // namespace msime::windows

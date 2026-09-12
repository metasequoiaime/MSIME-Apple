#pragma once
#include "CandidatePalette.h"
#include "TrayMenuLayout.h"
#include <functional>
// windows.h first: its DrawText macro has to reach the Direct2D declarations,
// and NOMINMAX keeps its min/max macros away from the standard library.
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <msimeui/DeviceResources.h>

namespace msime::windows {
// The tray menu the shipped language bar opens: a composed card of commands,
// shown on request and dismissed as soon as it loses the pointer or focus. It
// owns no input state and never takes focus from the application being typed
// into.
class TrayMenuWindow final {
public:
  // Runs a chosen command. Returning false leaves the menu open so a failed
  // command does not look like it was accepted.
  using Command = std::function<bool(TrayMenuCommand)>;
  // The live floating toolbar state, so the row shows a switch rather than a
  // guess.
  using ToolbarState = std::function<bool()>;
  TrayMenuWindow(TrayMenuCapabilities capabilities, Command command,
                 ToolbarState toolbar_state);
  ~TrayMenuWindow();
  TrayMenuWindow(const TrayMenuWindow &) = delete;
  TrayMenuWindow &operator=(const TrayMenuWindow &) = delete;
  // Open under the tray icon, in work area pixels.
  void show(int icon_center_x, int icon_top);
  void hide();
  void set_palette(CandidatePalette palette);
  bool visible() const;
  bool failed() const { return failed_; }
  HWND handle() const { return window_; }

private:
  static LRESULT CALLBACK procedure(HWND, UINT, WPARAM, LPARAM) noexcept;
  void paint();
  std::optional<size_t> hit(int x, int y) const;
  void choose(size_t index);
  TrayMenuCapabilities capabilities_;
  Command command_;
  ToolbarState toolbar_state_;
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
  TrayMenuMetrics metrics_;
  std::vector<TrayMenuItem> items_;
  HWND window_ = nullptr;
  size_t hovered_ = static_cast<size_t>(-1);
  unsigned dpi_ = 96;
  bool failed_ = false;
};
} // namespace msime::windows

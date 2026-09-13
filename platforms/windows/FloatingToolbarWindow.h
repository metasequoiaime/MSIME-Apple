#pragma once
#include "ModeWindow.h"
#include <functional>
#include <array>
#include <optional>
// windows.h first: its DrawText macro has to reach the Direct2D declarations.
#include <windows.h>
#include <msimeui/DeviceResources.h>

namespace msime::windows {
struct CharacterSetClick {};
using CharacterSetClickWorker = SingleClickWorker<CharacterSetClick>;
class FloatingToolbarWindow final {
public:
  using Reader = std::function<std::optional<ModePresentation>()>;
  using Click = std::function<void(const ModeClick &)>;
  using Action = std::function<void()>;
  FloatingToolbarWindow(Reader reader, Click click);
  ~FloatingToolbarWindow();
  // Share the candidate card's resolved tokens so one theme covers the surface.
  void set_palette(CandidatePalette palette);
  void set_scale(double scale) { scale_ = scale; }
  void set_font_size(int size) { font_size_ = size; }
  void set_items(std::array<bool, 6> items) { items_ = items; }
  void set_character_set_reader(std::function<std::optional<bool>()> reader) {
    character_set_reader_ = std::move(reader);
  }
  void set_settings_action(Action action) { settings_action_ = std::move(action); }
  void set_character_set_action(Action action) { character_set_action_ = std::move(action); }
  void set_emoji_action(Action action) { emoji_action_ = std::move(action); }
  void set_handwriting_action(Action action) { handwriting_action_ = std::move(action); }
  void set_keyboard_action(Action action) { keyboard_action_ = std::move(action); }
  void set_voice_action(Action action) { voice_action_ = std::move(action); }
  void set_about_action(Action action) { about_action_ = std::move(action); }
  void set_hide_action(Action action) { hide_action_ = std::move(action); }
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
  Action settings_action_;
  Action character_set_action_;
  Action emoji_action_;
  Action handwriting_action_;
  Action keyboard_action_;
  Action voice_action_;
  Action about_action_;
  Action hide_action_;
  HWND window_ = nullptr;
  std::optional<ModePresentation> shown_;
  std::optional<bool> shown_character_set_;
  std::function<std::optional<bool>()> character_set_reader_;
  bool failed_ = false;
  double scale_ = 1.0;
  int font_size_ = 24;
  std::array<bool, 6> items_{true, true, true, true, false, true};
};
} // namespace msime::windows

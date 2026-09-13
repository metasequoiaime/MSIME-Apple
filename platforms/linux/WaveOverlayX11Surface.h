#pragma once

#include "WaveOverlaySurface.h"

#include <X11/Xlib.h>

#include <cstdint>
#include <functional>
#include <utility>

namespace msime::linux_host {

// Lightweight X11 fallback for desktops that do not expose a layer-shell
// protocol. The surface never takes focus and accepts pointer input only in
// its explicit action-button regions.
class WaveOverlayX11Surface final : public WaveOverlaySurface {
 public:
  explicit WaveOverlayX11Surface(ActionHandler action_handler = {})
      : action_handler_(std::move(action_handler)) {}
  ~WaveOverlayX11Surface() override;

  bool show(const WaveOverlayModel &model) override;
  void update(const WaveOverlayModel &model) override;
  void hide() override;

 private:
  bool ensure_window();
  void draw(const WaveOverlayModel &model);
  void pump_events();
  void set_input_region(bool actions_visible);
  bool hit_test_action(int x, int y, WaveOverlayModel::Action &action) const;
  void destroy_window();

  Display *display_ = nullptr;
  Window window_ = 0;
  GC gc_ = nullptr;
  XFontSet font_set_ = nullptr;
  unsigned long background_ = 0;
  unsigned long foreground_ = 0;
  unsigned long accent_ = 0;
  bool visible_ = false;
  ActionHandler action_handler_;
  WaveOverlayModel::Action pressed_action_ = WaveOverlayModel::Action::Confirm;
  bool action_pressed_ = false;
  bool actions_visible_ = false;
};

}  // namespace msime::linux_host

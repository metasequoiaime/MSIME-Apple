#pragma once

#include "WaveOverlaySurface.h"

#include <X11/Xlib.h>

#include <cstdint>

namespace msime::linux_host {

// Lightweight X11 fallback for desktops that do not expose a layer-shell
// protocol. The surface never takes focus; actions remain available through
// the IBus properties menu.
class WaveOverlayX11Surface final : public WaveOverlaySurface {
 public:
  WaveOverlayX11Surface() = default;
  ~WaveOverlayX11Surface() override;

  bool show(const WaveOverlayModel &model) override;
  void update(const WaveOverlayModel &model) override;
  void hide() override;

 private:
  bool ensure_window();
  void draw(const WaveOverlayModel &model);
  void destroy_window();

  Display *display_ = nullptr;
  Window window_ = 0;
  GC gc_ = nullptr;
  XFontSet font_set_ = nullptr;
  unsigned long background_ = 0;
  unsigned long foreground_ = 0;
  unsigned long accent_ = 0;
  bool visible_ = false;
};

}  // namespace msime::linux_host

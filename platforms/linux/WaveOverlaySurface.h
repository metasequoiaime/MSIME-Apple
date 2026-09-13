#pragma once
#include "WaveOverlayModel.h"
namespace msime::linux_host {
class WaveOverlaySurface {
 public:
  virtual ~WaveOverlaySurface() = default;
  virtual bool show(const WaveOverlayModel&) = 0;
  virtual void update(const WaveOverlayModel&) = 0;
  virtual void hide() = 0;
};
}

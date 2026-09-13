#pragma once
#include "WaveOverlayModel.h"
#include <functional>
namespace msime::linux_host {
class WaveOverlaySurface {
 public:
  using ActionHandler = std::function<void(WaveOverlayModel::Action)>;
  virtual ~WaveOverlaySurface() = default;
  virtual bool show(const WaveOverlayModel&) = 0;
  virtual void update(const WaveOverlayModel&) = 0;
  virtual void hide() = 0;
};
}

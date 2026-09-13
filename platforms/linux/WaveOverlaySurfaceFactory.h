#pragma once

#include "WaveOverlaySurface.h"
#include <ibus.h>

#include <memory>

namespace msime::linux_host {

std::unique_ptr<WaveOverlaySurface> create_wave_overlay_surface(IBusEngine *engine);

}  // namespace msime::linux_host

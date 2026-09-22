#pragma once

#include <optional>

namespace msime::fcitx_host {

// Reads the freedesktop color-scheme portal value. nullopt means that no
// portal is available; callers retain the previous value in that case.
std::optional<bool> fcitx_system_dark_theme();

}  // namespace msime::fcitx_host

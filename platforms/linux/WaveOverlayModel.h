#pragma once

#include <algorithm>
#include <array>

namespace msime::linux_host {

struct WaveOverlayModel {
  enum class Action { Cancel, Confirm };
  enum class CompactStatus { None, Recognizing, Processing };
  static constexpr std::size_t kLevelCount = 12;
  std::array<float, kLevelCount> levels{};
  bool listening = false;
  bool show_transcript = true;
  bool actions_visible = false;
  Action pressed_action = Action::Confirm;
  CompactStatus compact_status = CompactStatus::None;

  void set_input_level(float value) {
    value = std::clamp(value, 0.0f, 1.0f);
    for (std::size_t i = 0; i < kLevelCount; ++i) {
      const float center = 1.0f - static_cast<float>(i) / kLevelCount;
      levels[i] = std::clamp(value * (0.55f + center * 0.45f), 0.0f, 1.0f);
    }
  }
};

}  // namespace msime::linux_host

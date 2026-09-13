#pragma once

#include <algorithm>
#include <array>
#include <string>
#include <utility>

namespace msime::linux_host {

struct WaveOverlayModel {
  enum class Action { Cancel, Confirm };
  enum class CompactStatus { None, Recognizing, Processing };
  static constexpr std::size_t kLevelCount = 12;
  std::array<float, kLevelCount> levels{};
  bool listening = false;
  bool show_transcript = true;
  bool actions_visible = false;
  std::string transcript;

  void set_transcript(std::string value) {
    constexpr std::size_t kVisibleCharacters = 160;
    std::size_t count = 0;
    for (auto it = value.rbegin(); it != value.rend(); ++it) {
      if ((static_cast<unsigned char>(*it) & 0xc0) != 0x80) ++count;
      if (count == kVisibleCharacters) {
        value.erase(0, static_cast<std::size_t>(it.base() - value.begin() - 1));
        break;
      }
    }
    transcript = std::move(value);
  }
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

#pragma once
#include <array>
#include <cstdint>
#include <mutex>
#include <nlohmann/json.hpp>
#include <optional>

namespace msime::windows {
struct FloatingToolbarSettings {
  unsigned scale_percent = 100;
  unsigned font_size = 24;
  std::array<bool, 6> items{true, true, true, true, false, true};
  bool valid() const {
    return scale_percent >= 75 && scale_percent <= 150 &&
           font_size >= 16 && font_size <= 28;
  }
};

inline std::optional<FloatingToolbarSettings>
floating_toolbar_settings(const nlohmann::json &preferences) {
  try {
    if (!preferences.is_object()) return std::nullopt;
    const auto toolbar = preferences.value("floating_toolbar", nlohmann::json::object());
    if (!toolbar.is_object()) return std::nullopt;
    FloatingToolbarSettings result;
    for (const auto &[key, target] :
         {std::pair{"scale_percent", &result.scale_percent},
          std::pair{"font_size", &result.font_size}}) {
      if (!toolbar.contains(key)) continue;
      const auto &value = toolbar.at(key);
      if (!value.is_number_integer() || value < 0 || value > 200)
        return std::nullopt;
      *target = value.get<unsigned>();
    }
    constexpr const char *names[] = {"character_set", "punctuation", "fullwidth",
                                     "emoji", "screen_keyboard", "settings"};
    for (size_t i = 0; i < result.items.size(); ++i)
      result.items[i] = toolbar.value(names[i], result.items[i]);
    return result.valid() ? std::optional{result} : std::nullopt;
  } catch (...) {
    return std::nullopt;
  }
}

// Only presentation settings cross threads. Keep the newest revision even
// after consumption, so a delayed publisher cannot restore an older layout.
class FloatingToolbarMailbox {
public:
  bool publish(uint64_t revision, FloatingToolbarSettings value) {
    if (!value.valid()) return false;
    std::lock_guard lock(mutex_);
    if (revision_ && revision <= *revision_) return false;
    revision_ = revision;
    pending_ = value;
    return true;
  }
  std::optional<FloatingToolbarSettings> take() {
    std::lock_guard lock(mutex_);
    const auto result = pending_;
    pending_.reset();
    return result;
  }
private:
  std::mutex mutex_;
  std::optional<uint64_t> revision_;
  std::optional<FloatingToolbarSettings> pending_;
};
} // namespace msime::windows

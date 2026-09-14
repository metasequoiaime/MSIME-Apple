#pragma once
#include <algorithm>
#include <cstdint>
#include <mutex>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <vector>

namespace msime::windows {
struct CandidateFontSettings {
  std::string family = "Segoe UI";
  std::vector<std::string> fallback;
  unsigned size = 18;
  unsigned preedit_size = 15;
  bool valid() const {
    const auto name_valid = [](const std::string &name) {
      return !name.empty() && name.size() <= 128 &&
             std::none_of(name.begin(), name.end(),
                          [](unsigned char c) { return c < 32 || c == 127; });
    };
    return name_valid(family) && fallback.size() <= 32 &&
           std::all_of(fallback.begin(), fallback.end(), name_valid) &&
           size >= 12 && size <= 32 && preedit_size >= 12 && preedit_size <= 32;
  }
  bool operator==(const CandidateFontSettings &other) const {
    return family == other.family && fallback == other.fallback &&
           size == other.size && preedit_size == other.preedit_size;
  }
};

// Only display settings cross the thread boundary, never the full preferences
// document (which can contain credentials), candidates, or composition state.
inline std::optional<CandidateFontSettings>
candidate_font_settings(const nlohmann::json &preferences) {
  try {
    if (!preferences.is_object())
      return std::nullopt;
    CandidateFontSettings result;
    if (preferences.contains("candidate_english_font") &&
        !preferences.at("candidate_english_font").is_null())
      result.family =
          preferences.at("candidate_english_font").get<std::string>();
    result.fallback = preferences.value(
        "candidate_fallback_fonts",
        std::vector<std::string>{"Noto Sans SC", "Microsoft YaHei"});
    for (const auto &[key, target] :
         {std::pair{"candidate_font_size", &result.size},
          std::pair{"candidate_preedit_font_size", &result.preedit_size}}) {
      if (!preferences.contains(key))
        continue;
      if (!preferences.at(key).is_number_integer())
        return std::nullopt;
      const auto size = preferences.at(key).get<int64_t>();
      if (size < 12 || size > 32)
        return std::nullopt;
      *target = static_cast<unsigned>(size);
    }
    return result.valid() ? std::optional{std::move(result)} : std::nullopt;
  } catch (...) {
    return std::nullopt;
  }
}

class CandidateFontMailbox {
public:
  bool publish(uint64_t revision, CandidateFontSettings value) {
    if (!value.valid())
      return false;
    std::lock_guard lock(mutex_);
    if (revision_ && revision <= *revision_)
      return false;
    revision_ = revision;
    pending_ = std::move(value);
    return true;
  }
  std::optional<CandidateFontSettings> take() {
    std::lock_guard lock(mutex_);
    auto result = std::move(pending_);
    pending_.reset();
    return result;
  }

private:
  std::mutex mutex_;
  std::optional<uint64_t> revision_;
  std::optional<CandidateFontSettings> pending_;
};
} // namespace msime::windows

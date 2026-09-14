#pragma once
#include "CandidatePalette.h"
#include "CandidateSkinAssets.h"
#include <mutex>
#include <nlohmann/json.hpp>

namespace msime::windows {
inline nlohmann::json
candidate_theme_values(const nlohmann::json &preferences) {
  nlohmann::json result = nlohmann::json::object();
  if (preferences.contains("candidate_skin") &&
      preferences.at("candidate_skin").is_string()) {
    const auto id = preferences.at("candidate_skin").get<std::string>();
    if (valid_candidate_skin_id(id))
      result["candidate_skin"] = id;
  }
  for (const char *key : {"theme", "candidate_theme", "candidate_text_color",
                          "candidate_number_color", "candidate_surface_color",
                          "candidate_border_color", "candidate_selected_color",
                          "candidate_hover_color", "candidate_accent_color"}) {
    if (preferences.contains(key) && preferences.at(key).is_string()) {
      const auto value = preferences.at(key).get<std::string>();
      if (value.size() <= 32)
        result[key] = value;
    }
  }
  return result;
}
inline bool candidate_theme_dark(const nlohmann::json &values,
                                 bool system_dark) {
  const auto theme = values.value("candidate_theme", std::string("follow"));
  if (theme == "dark" || theme == "light")
    return theme == "dark";
  const auto global = values.value("theme", std::string("dark"));
  return global == "system" ? system_dark : global != "light";
}
inline CandidatePalette candidate_theme_palette(CandidatePalette base,
                                                const nlohmann::json &values) {
  for (const auto &[key, member] :
       {std::pair{"candidate_text_color", &CandidatePalette::text},
        std::pair{"candidate_number_color", &CandidatePalette::number},
        std::pair{"candidate_surface_color", &CandidatePalette::surface},
        std::pair{"candidate_border_color", &CandidatePalette::border},
        std::pair{"candidate_selected_color", &CandidatePalette::selected},
        std::pair{"candidate_hover_color", &CandidatePalette::hover},
        std::pair{"candidate_accent_color", &CandidatePalette::accent}}) {
    if (values.contains(key) && values.at(key).is_string())
      base.*member =
          parse_css_color(values.at(key).get<std::string>(), base.*member);
  }
  return base;
}
// Only the small display projection crosses the preference/UI thread boundary.
class CandidateThemeMailbox {
public:
  void publish(const nlohmann::json &preferences) {
    auto values = candidate_theme_values(preferences);
    std::lock_guard lock(mutex_);
    pending_ = std::move(values);
  }
  std::optional<nlohmann::json> take() {
    std::lock_guard lock(mutex_);
    auto result = std::move(pending_);
    pending_.reset();
    return result;
  }

private:
  std::mutex mutex_;
  std::optional<nlohmann::json> pending_;
};
} // namespace msime::windows

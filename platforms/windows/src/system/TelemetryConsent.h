#pragma once
#include <nlohmann/json.hpp>

namespace msime::windows {
// Whether the user turned on the shared `telemetry_enabled` preference. Anything other than an explicit true - an absent key from a document that predates the switch, a malformed value, a document that is not an object - is off, because reporting is opt-in.
inline bool telemetry_consented(const nlohmann::json &preferences) {
  const auto value = preferences.find("telemetry_enabled");
  return value != preferences.end() && value->is_boolean() && value->get<bool>();
}
} // namespace msime::windows

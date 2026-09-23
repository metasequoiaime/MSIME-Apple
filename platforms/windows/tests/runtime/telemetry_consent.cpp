#include "TelemetryConsent.h"
#include <stdexcept>

using msime::windows::telemetry_consented;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Telemetry consent validation failed");
}
int main() {
  // Only an explicit true sends anything.
  require(telemetry_consented(nlohmann::json{{"telemetry_enabled", true}}));
  require(!telemetry_consented(nlohmann::json{{"telemetry_enabled", false}}));
  // A document written before the switch existed stays silent after an upgrade.
  require(!telemetry_consented(nlohmann::json::object()));
  require(!telemetry_consented(nlohmann::json{{"clipboard_history", true}}));
  // Malformed values and non-object documents are off rather than an error at startup.
  require(!telemetry_consented(nlohmann::json{{"telemetry_enabled", "true"}}));
  require(!telemetry_consented(nlohmann::json{{"telemetry_enabled", 1}}));
  require(!telemetry_consented(nlohmann::json{{"telemetry_enabled", nullptr}}));
  require(!telemetry_consented(nlohmann::json()));
  require(!telemetry_consented(nlohmann::json::array({true})));
  return 0;
}

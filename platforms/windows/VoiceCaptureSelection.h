#pragma once
#include <nlohmann/json.hpp>
#include <string>

namespace msime::windows {
struct VoiceCaptureSelection {
  std::string backend;
  std::string device_id;
  bool supported() const {
    return backend.empty() || backend == "auto" || backend == "windows";
  }
};
inline VoiceCaptureSelection voice_capture_selection(const nlohmann::json &input) {
  return {input.value("capture_backend", std::string{}),
          input.value("capture_device", std::string{})};
}
} // namespace msime::windows

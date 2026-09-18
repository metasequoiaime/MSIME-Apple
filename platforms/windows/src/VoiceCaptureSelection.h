#pragma once
#include <nlohmann/json.hpp>
#include <algorithm>
#include <cctype>
#include <string>

namespace msime::windows {
struct VoiceCaptureSelection {
  std::string backend;
  std::string device_id;
  bool supported() const {
    const bool backend_ok = backend.empty() || backend == "auto" || backend == "windows";
    const bool device_ok = device_id.size() <= 512 &&
                           std::none_of(device_id.begin(), device_id.end(), [](unsigned char ch) {
                             return std::iscntrl(ch) != 0;
                           });
    return backend_ok && device_ok;
  }
};
inline VoiceCaptureSelection voice_capture_selection(const nlohmann::json &input) {
  return {input.value("capture_backend", std::string{}),
          input.value("capture_device", std::string{})};
}
} // namespace msime::windows

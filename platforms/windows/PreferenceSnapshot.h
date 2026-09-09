#pragma once
#include "msime_client.h"
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>

namespace msime::windows {
// Immutable validated publication value. Loading may block on the shared store
// lock: call on a settings worker, never inside an input task/focus callback.
class PreferenceSnapshot final {
public:
  static PreferenceSnapshot load(const std::string &directory) {
    std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
        msime_client_load_preferences(
            reinterpret_cast<const uint8_t *>(directory.data()),
            directory.size()),
        msime_client_string_free);
    if (!raw)
      throw std::runtime_error("Missing shared preferences response");
    auto response = nlohmann::json::parse(raw.get());
    if (!response.at("ok").get<bool>())
      throw std::runtime_error("Shared preferences load failed");
    auto value = response.at("value");
    const auto revision = value.at("revision").get<uint64_t>();
    auto serialized = value.dump();
    if (serialized.size() > 16384)
      throw std::runtime_error("Shared preferences snapshot too large");
    return PreferenceSnapshot(revision, std::move(serialized));
  }
  uint64_t revision() const { return revision_; }
  const std::string &serialized() const { return serialized_; }

private:
  PreferenceSnapshot(uint64_t revision, std::string serialized)
      : revision_(revision), serialized_(std::move(serialized)) {}
  uint64_t revision_;
  std::string serialized_;
};
} // namespace msime::windows

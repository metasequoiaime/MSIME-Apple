#pragma once
#include <filesystem>
#include <fstream>
#include <functional>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>

namespace msime::windows {
// Only orchestration belongs here. Resource verification and Engine dictionary
// preparation stay in the shared Host API, supplied by the native executable.
inline std::filesystem::path prepare_host_state_in_directory(
    const std::filesystem::path &resources,
    const std::filesystem::path &requested_state,
    const std::function<std::string(const std::string &)> &prepare) {
  if (!resources.is_absolute() || !requested_state.is_absolute() ||
      !std::filesystem::is_directory(resources))
    throw std::runtime_error("Absolute resource and new state paths required");
  const auto state = requested_state.lexically_normal();
  const auto request = nlohmann::json{
      {"resources", std::filesystem::canonical(resources).u8string()},
      {"state_root", state.u8string()}}.dump();
  if (request.size() > 16384)
    throw std::runtime_error("Preparation request oversized");
  const auto response = nlohmann::json::parse(prepare(request));
  if (!response.value("ok", false) || !response.at("value").is_object())
    throw std::runtime_error("Shared host preparation failed");
  const auto document = response.at("value").dump(2) + "\n";
  if (document.size() > 16384)
    throw std::runtime_error("Prepared configuration oversized");
  const auto temporary = state / ".runtime-options-prepared";
  const auto destination = state / "runtime-options.json";
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::out);
    output.write(document.data(), static_cast<std::streamsize>(document.size()));
    output.close();
    if (!output)
      throw std::runtime_error("Cannot write prepared configuration");
  }
  // A same-directory hard link publishes complete contents without replacing
  // any destination created concurrently. Unsupported filesystems fail closed.
  // Do not remove prepared data on failure: the user may need it to diagnose.
  std::filesystem::create_hard_link(temporary, destination);
  std::filesystem::remove(temporary);
  return destination;
}

inline std::filesystem::path prepare_host_state(
    const std::filesystem::path &resources,
    const std::filesystem::path &requested_state,
    const std::function<std::string(const std::string &)> &prepare) {
  // create_directory is exclusive: never prepare against live or existing state.
  // Its parent must already exist. On Windows the new directory inherits the
  // user's LocalAppData ACL; this tool must run as that user, not the installer.
  const auto state = requested_state.lexically_normal();
  if (!resources.is_absolute() || !requested_state.is_absolute() ||
      !std::filesystem::is_directory(resources))
    throw std::runtime_error("Absolute resource and new state paths required");
  if (!std::filesystem::create_directory(state))
    throw std::runtime_error("A fresh state directory is required");
  return prepare_host_state_in_directory(resources, state, prepare);
}
} // namespace msime::windows

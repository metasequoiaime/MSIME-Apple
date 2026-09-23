#pragma once

#include "msime_client.h"

#include <filesystem>
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>

namespace msime::linux_host {

// Bring runtime options written before a package upgrade up to the installed dictionary generation: the Host API prepares the new generation, replays the user dictionary into it and rewrites the file. Returns true when the file was rewritten and false when it was already current. Throws when preparation failed; the file is then left exactly as it was and the previous generation stays usable, so the caller carries on and the next start tries again. The Host API error is not surfaced because it can name private paths.
inline bool refresh_runtime_options(const std::filesystem::path &path) {
  const auto text = path.string();
  std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
      msime_client_refresh_host(reinterpret_cast<const uint8_t *>(text.data()), text.size()),
      msime_client_string_free);
  if (!raw) throw std::runtime_error("runtime options refresh failed");
  const auto result = nlohmann::json::parse(raw.get());
  if (!result.value("ok", false) || !result.at("value").is_boolean())
    throw std::runtime_error("runtime options refresh failed");
  return result.at("value").get<bool>();
}

} // namespace msime::linux_host

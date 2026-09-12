#include "msime_client.h"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>


namespace {
std::string default_model_path(const char *program) {
  if (const char *value = std::getenv("MSIME_HANDWRITING_MODEL"); value && *value)
    return value;
  std::vector<std::filesystem::path> candidates;
  if (const char *value = std::getenv("XDG_DATA_HOME"); value && *value)
    candidates.emplace_back(std::filesystem::path(value) / "msime-client/handwriting/handwriting-zh_CN.model");
  if (const char *value = std::getenv("XDG_DATA_DIRS"); value && *value) {
    std::string dirs(value); std::size_t start = 0;
    while (start <= dirs.size()) {
      const auto end = dirs.find(':', start);
      const auto dir = dirs.substr(start, end == std::string::npos ? end : end - start);
      if (!dir.empty())
        candidates.emplace_back(std::filesystem::path(dir) / "msime-client/handwriting/handwriting-zh_CN.model");
      if (end == std::string::npos) break;
      start = end + 1;
    }
  }
  std::error_code error;
  const auto executable = std::filesystem::absolute(program, error);
  if (!error)
    candidates.emplace_back(executable.parent_path().parent_path() /
                            "share/msime-client/handwriting/handwriting-zh_CN.model");
  candidates.emplace_back("/usr/local/share/msime-client/handwriting/handwriting-zh_CN.model");
  candidates.emplace_back("/usr/share/msime-client/handwriting/handwriting-zh_CN.model");
  for (const auto &candidate : candidates)
    if (std::filesystem::is_regular_file(candidate))
      return candidate.string();
  return {};
}

} // namespace

int main(int argc, char **argv) {
  const bool local = argc >= 2 && std::string(argv[1]) == "--local";
  const bool provider = !local && argc == 2;
  if ((!local && !provider) || (provider && argv[1][0] != '/'))
    return 2;
  const std::string endpoint = local
      ? (argc == 3 ? argv[2] : default_model_path(argv[0]))
      : argv[1];
  if (endpoint.empty() || endpoint[0] != '/')
    return 2;
  std::array<char, 262145> buffer;
  std::cin.read(buffer.data(), buffer.size());
  const auto length = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || length == 0 || length > 262144)
    return 2;
  std::unique_ptr<char, decltype(&msime_client_string_free)> result(
      local ? msime_client_handwriting_local_request(
                  reinterpret_cast<const uint8_t *>(buffer.data()), length,
                  reinterpret_cast<const uint8_t *>(endpoint.data()), endpoint.size())
            : msime_client_handwriting_provider_request(
                  reinterpret_cast<const uint8_t *>(buffer.data()), length,
                  reinterpret_cast<const uint8_t *>(endpoint.data()), endpoint.size()),
      msime_client_string_free);
  if (!result)
    return 1;
  try {
    auto document = nlohmann::json::parse(result.get());
    const bool ok = document.at("ok").get<bool>();
    std::cout << document.dump() << '\n';
    return std::cout ? (ok ? 0 : 1) : 1;
  } catch (...) {
    return 1;
  }
}

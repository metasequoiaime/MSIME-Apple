#include "msime_client.h"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

std::string local_resources(int argc, char **argv, bool *local) {
  *local = argc >= 2 && std::string(argv[1]) == "--local";
  if (!*local)
    return argc == 2 ? argv[1] : std::string{};
  if (argc == 3)
    return argv[2];
  if (argc != 2)
    return {};
  std::vector<std::filesystem::path> candidates;
  if (const char *value = std::getenv("MSIME_EMOJI_RESOURCES"); value && *value)
    candidates.emplace_back(value);
  if (const char *value = std::getenv("XDG_DATA_HOME"); value && *value)
    candidates.emplace_back(std::filesystem::path(value) / "msime-client/emoji");
  if (const char *value = std::getenv("XDG_DATA_DIRS"); value && *value) {
    std::string dirs(value);
    std::size_t start = 0;
    while (start <= dirs.size()) {
      const auto end = dirs.find(':', start);
      const auto dir = dirs.substr(start, end == std::string::npos ? end : end - start);
      if (!dir.empty())
        candidates.emplace_back(std::filesystem::path(dir) / "msime-client/emoji");
      if (end == std::string::npos) break;
      start = end + 1;
    }
  }
  candidates.emplace_back("/usr/local/share/msime-client/emoji");
  candidates.emplace_back("/usr/share/msime-client/emoji");
  for (const auto &candidate : candidates)
    if (std::filesystem::exists(candidate) && std::filesystem::is_directory(candidate))
      return candidate.string();
  return {};
}

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--help") {
    std::cout << "Usage: msime-client-emoji [--local [resources]] <socket-or-resources>\n";
    return 0;
  }
  bool local = false;
  const auto target = local_resources(argc, argv, &local);
  if (target.empty() || target[0] != '/')
    return 2;
  std::array<char, 16385> buffer;
  std::cin.read(buffer.data(), buffer.size());
  const auto length = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || length == 0 || length > 16384)
    return 2;
  std::unique_ptr<char, decltype(&msime_client_string_free)> result(
      local ? msime_client_emoji_catalog_request(
                  reinterpret_cast<const uint8_t *>(buffer.data()), length,
                  reinterpret_cast<const uint8_t *>(target.data()), target.size())
            : msime_client_emoji_provider_request(
                  reinterpret_cast<const uint8_t *>(buffer.data()), length,
                  reinterpret_cast<const uint8_t *>(target.data()), target.size()),
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

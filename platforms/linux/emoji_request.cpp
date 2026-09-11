#include "msime_client.h"

#include <array>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>

int main(int argc, char **argv) {
  const bool local = argc == 3 && std::string(argv[1]) == "--local";
  if ((!local && argc != 2) || (local ? argv[2][0] != '/' : argv[1][0] != '/'))
    return 2;
  std::array<char, 16385> buffer;
  std::cin.read(buffer.data(), buffer.size());
  const auto length = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || length == 0 || length > 16384)
    return 2;
  const std::string target = local ? argv[2] : argv[1];
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

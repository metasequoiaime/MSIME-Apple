#include "msime_client.h"

#include <array>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>

int main(int argc, char **argv) {
  const bool local = argc == 3 && std::string(argv[1]) == "--local";
  const bool provider = argc == 2;
  if ((!local && !provider) || (local ? argv[2][0] != '/' : argv[1][0] != '/'))
    return 2;
  std::array<char, 262145> buffer;
  std::cin.read(buffer.data(), buffer.size());
  const auto length = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || length == 0 || length > 262144)
    return 2;
  const std::string endpoint = local ? argv[2] : argv[1];
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

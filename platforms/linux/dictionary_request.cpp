#include "msime_client.h"
#include <iostream>
#include <array>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>

int main(int argc, char **) {
  if (argc != 1)
    return 2;
  std::array<char, 65537> buffer;
  std::cin.read(buffer.data(), buffer.size());
  const auto length = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || length == 0 || length > 65536)
    return 2;
  std::unique_ptr<char, decltype(&msime_client_string_free)> result(
      msime_client_dictionary(reinterpret_cast<const uint8_t *>(buffer.data()),
                              length),
      msime_client_string_free);
  if (!result)
    return 1;
  try {
    auto document = nlohmann::json::parse(result.get());
    const bool ok = document.at("ok").get<bool>();
    std::cout << document.dump() << '\n';
    if (!std::cout)
      return 1;
    return ok ? 0 : 1;
  } catch (...) {
    // Never print parser errors or request data; they can contain user entries.
    return 1;
  }
}

#include "msime_client.h"
#include <array>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>

int main(int argc, char **argv) {
  if (argc != 2 || argv[1][0] != '/') return 2;
  std::array<char, 4097> input;
  std::cin.read(input.data(), input.size());
  const auto size = static_cast<size_t>(std::cin.gcount());
  if (std::cin.bad() || size == 0 || size == input.size()) return 2;
  try {
    const auto request = nlohmann::json{
        {"directory", argv[1]}, {"text", std::string(input.data(), size)}}.dump();
    std::unique_ptr<char, decltype(&msime_client_string_free)> result(
        msime_client_capture_clipboard_history(
            reinterpret_cast<const uint8_t *>(request.data()), request.size()),
        msime_client_string_free);
    if (!result) return 1;
    const auto document = nlohmann::json::parse(result.get());
    if (!document.value("ok", false)) return 1;
    return document.at("value").value("captured", false) ? 0 : 3;
  } catch (...) { return 1; }
}

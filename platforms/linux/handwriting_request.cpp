#include "msime_client.h"

#include <array>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <string>

namespace {
std::string default_model_path(const char *program) {
  if (const char *configured = std::getenv("MSIME_HANDWRITING_MODEL");
      configured && *configured)
    return configured;
  std::error_code error;
  const auto executable = std::filesystem::absolute(program, error);
  if (error)
    return {};
  return (executable.parent_path().parent_path() /
          "share/msime-client/handwriting/handwriting-zh_CN.model")
      .string();
}
} // namespace

int main(int argc, char **argv) {
  const bool local = argc >= 2 && std::string(argv[1]) == "--local";
  const bool provider = !local && argc == 2;
  if ((!local && !provider) || (provider && argv[1][0] != '/'))
    return 2;
  std::string endpoint;
  if (local) {
    if (argc > 3)
      return 2;
    endpoint = argc == 3 ? argv[2] : default_model_path(argv[0]);
    if (endpoint.empty() || endpoint[0] != '/')
      return 2;
  } else {
    endpoint = argv[1];
  }
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

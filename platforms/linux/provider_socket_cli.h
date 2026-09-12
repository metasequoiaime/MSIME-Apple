#pragma once

#include <cstdlib>
#include <string>

inline std::string msime_cli_provider_socket(int argc, char **argv,
                                             const char *environment,
                                             const char *default_name) {
  if (argc == 2 && argv[1][0] == '/')
    return argv[1];
  if (const auto *value = std::getenv(environment); value && *value)
    return value;
  if (const auto *runtime = std::getenv("XDG_RUNTIME_DIR"); runtime && *runtime)
    return std::string(runtime) + "/msime/" + default_name;
  return {};
}

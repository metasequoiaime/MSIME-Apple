#pragma once
#include <filesystem>
#include <nlohmann/json.hpp>

// Shared by the portable regression and the native pipe integration test.
// Caller owns an isolated temporary root and its cleanup. No user data/logging.
inline nlohmann::json test_host_options(const std::filesystem::path &root) {
  nlohmann::json result{{"api_version", 1},
                        {"preferences",
                         {{"scheme", "quanpin"},
                          {"learning", false},
                          {"candidate_page_size", 5},
                          {"chinese_punctuation", true}}}};
  for (const char *name : {"resources", "user_data", "cache", "dictionaries"}) {
    const auto directory = root / name;
    std::filesystem::create_directories(directory);
    result[name] = directory.u8string();
  }
  return result;
}

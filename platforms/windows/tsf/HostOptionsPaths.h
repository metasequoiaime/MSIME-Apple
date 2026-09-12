#pragma once
#include <filesystem>
#include <string>

namespace msime::tsf {
// Read the atomically published prepare_host document unchanged.
// The shared host validates the schema; never synthesize fallback data.
std::string read_prepared_host_options(const std::filesystem::path &file);
std::string default_host_options_json();
}

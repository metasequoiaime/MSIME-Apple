#include "HostOptionsPaths.h"
#include <fstream>

namespace msime::tsf {
std::string read_prepared_host_options(const std::filesystem::path &file) {
  // Match msime_client_create's limit; an extra byte detects truncation.
  constexpr std::size_t limit = 16384;
  std::ifstream stream(file, std::ios::binary);
  if (!stream) return {};
  std::string document(limit + 1, '\0');
  stream.read(document.data(), static_cast<std::streamsize>(document.size()));
  const auto length = stream.gcount();
  if (stream.bad() || length <= 0 || length > static_cast<std::streamsize>(limit)) return {};
  document.resize(static_cast<std::size_t>(length));
  return document;
}
}

#include "../DiagnosticLog.h"

#include <cassert>
#include <filesystem>
#include <fstream>
#include <string>
#include <unistd.h>

int main() {
  const auto directory = std::filesystem::temp_directory_path() /
                         ("msime-macos-diagnostic-" + std::to_string(getpid()));
  std::filesystem::remove_all(directory);
  std::filesystem::create_directories(directory);
  const auto log = directory / "diagnostic.log";

  msime_macos_diagnostic_configure(directory.string(), false);
  msime_macos_diagnostic_write("disabled_event");
  assert(!std::filesystem::exists(log));

  msime_macos_diagnostic_configure(directory.string(), true);
  msime_macos_diagnostic_write("focus_in");
  msime_macos_diagnostic_write("operation_failed operation=synthetic\nprivate");
  std::ifstream input(log);
  const std::string contents((std::istreambuf_iterator<char>(input)), {});
  assert(contents.find("focus_in") != std::string::npos);
  assert(contents.find("operation_failed operation=synthetic?private") !=
         std::string::npos);
  assert(contents.find("disabled_event") == std::string::npos);

  msime_macos_diagnostic_configure(directory.string(), false);
  msime_macos_diagnostic_write("after_disable");
  std::ifstream after(log);
  const std::string unchanged((std::istreambuf_iterator<char>(after)), {});
  assert(unchanged == contents);
  std::filesystem::remove_all(directory);
}

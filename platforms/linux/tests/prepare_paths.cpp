#include "../PreparePaths.h"

#include <cassert>
#include <filesystem>

int main() {
  const auto root = std::filesystem::temp_directory_path() / "msime-prepare-paths-test";
  std::error_code error;
  std::filesystem::remove_all(root, error);
  std::filesystem::create_directories(root / "share/msime-client/resources");

  const auto executable = root / "bin/msime-client-prepare";
  const auto expected = std::filesystem::canonical(root / "share/msime-client/resources");
  assert(msime_linux::installed_resource_directory(executable) == expected.string());
  assert(msime_linux::installed_resource_directory("bin/msime-client-prepare").empty());

  std::filesystem::remove_all(root, error);
  return 0;
}

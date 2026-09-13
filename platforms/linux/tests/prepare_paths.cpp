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
  std::filesystem::create_directories(root / "libdata/msime-client/resources");
  const auto custom_expected =
      std::filesystem::canonical(root / "libdata/msime-client/resources");
  assert(msime_linux::installed_resource_directory(
             executable, "../libdata/msime-client/resources") ==
         custom_expected.string());
  assert(msime_linux::installed_resource_directory(executable, "/etc/passwd").empty());
  assert(msime_linux::installed_resource_directory("bin/msime-client-prepare").empty());

  std::filesystem::remove_all(root, error);
  return 0;
}

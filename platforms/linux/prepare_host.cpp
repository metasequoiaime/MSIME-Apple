#include "msime_client.h"
#include "PreparePaths.h"

#include <cerrno>
#include <cstdlib>
#include <filesystem>
#include <fcntl.h>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {
struct Descriptor {
  int value;
  explicit Descriptor(int descriptor) : value(descriptor) {}
  ~Descriptor() { if (value >= 0) close(value); }
  Descriptor(const Descriptor &) = delete;
  Descriptor &operator=(const Descriptor &) = delete;
};

bool publish(const std::filesystem::path &state, const std::string &document) {
  Descriptor directory(open(state.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW));
  if (directory.value < 0) return false;
  auto pattern = (state / ".runtime-options-XXXXXX").string();
  std::vector<char> name(pattern.begin(), pattern.end());
  name.push_back('\0');
  Descriptor file(mkstemp(name.data()));
  if (file.value < 0) return false;
  const auto temporary = std::filesystem::path(name.data()).filename().string();
  bool success = false;
  size_t offset = 0;
  while (offset < document.size()) {
    const auto count = write(file.value, document.data() + offset, document.size() - offset);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    offset += static_cast<size_t>(count);
  }
  if (offset == document.size() && fsync(file.value) == 0) {
    // Publishing via a hard link is atomic and never replaces an existing file.
    success = linkat(directory.value, temporary.c_str(), directory.value,
                     "runtime-options.json", 0) == 0;
  }
  const bool removed = unlinkat(directory.value, temporary.c_str(), 0) == 0;
  return fsync(directory.value) == 0 && success && removed;
}
} // namespace

int main(int argc, char **argv) {
  if (argc == 2 && std::string(argv[1]) == "--help") {
    std::cout << "Usage: msime-client-prepare <absolute-resource-directory> <absolute-new-state-directory>\n"
                 "       msime-client-prepare --installed <absolute-new-state-directory>\n"
                 "The state directory must not exist; its parent must exist.\n"
                 "--installed uses the resource bundle installed beside this executable.\n"
                 "Prints the new runtime-options.json path on success.\n";
    return 0;
  }
  if (argc != 3) {
    std::cerr << "Usage: msime-client-prepare <absolute-resource-directory> <absolute-new-state-directory>\n"
                 "       msime-client-prepare --installed <absolute-new-state-directory>\n";
    return 2;
  }
  try {
    const bool installed = std::string(argv[1]) == "--installed";
    std::filesystem::path resources;
    const std::filesystem::path requested_state(argv[2]);
    if (installed) {
      std::error_code error;
      const auto executable = std::filesystem::read_symlink("/proc/self/exe", error);
      if (error || !executable.is_absolute()) {
        std::cerr << "Cannot locate the installed executable resource bundle\n";
        return 1;
      }
      const auto discovered = msime_linux::installed_resource_directory(executable);
      if (discovered.empty()) {
        std::cerr << "Installed Engine resources were not found; provide a packaged resource bundle\n";
        return 1;
      }
      resources = discovered;
    } else {
      resources = argv[1];
    }
    if (!resources.is_absolute() || !requested_state.is_absolute() ||
        !std::filesystem::is_directory(resources)) {
      std::cerr << "Resource and new state directories must use absolute paths\n";
      return 2;
    }
    const auto state = requested_state.lexically_normal();
    const auto request = nlohmann::json({{"resources", std::filesystem::canonical(resources).string()},
                                       {"state_root", state.string()}}).dump();
    if (request.size() > 16384) return 2;
    umask(0077);
    if (mkdir(state.c_str(), 0700) != 0) {
      std::cerr << "Cannot create a fresh state directory; existing state is never replaced\n";
      return 1;
    }
    std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
        msime_client_prepare_host(reinterpret_cast<const uint8_t *>(request.data()), request.size()),
        msime_client_string_free);
    if (!raw) throw std::runtime_error("prepare failed");
    const auto result = nlohmann::json::parse(raw.get());
    if (!result.value("ok", false) || !result.at("value").is_object()) {
      std::cerr << "State preparation failed; check the pinned resources and use a fresh directory to retry\n";
      return 1;
    }
    if (!publish(state, result.at("value").dump(2) + "\n")) {
      std::cerr << "Cannot publish runtime configuration; prepared data has been retained\n";
      return 1;
    }
    std::cout << (state / "runtime-options.json").string() << '\n';
    return std::cout ? 0 : 1;
  } catch (...) {
    // Host diagnostics can contain private paths; do not forward them.
    std::cerr << "State preparation failed; existing and partially prepared data has been retained\n";
    return 1;
  }
}

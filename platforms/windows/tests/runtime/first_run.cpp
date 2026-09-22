#include "FirstRun.h"
#include <chrono>
#include <iostream>

int main() {
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() /
      ("msime-first-run-" + std::to_string(
          std::chrono::steady_clock::now().time_since_epoch().count()));
  if (!fs::create_directory(root)) return 1;
  try {
    const auto executable = root / "installed server";
    fs::create_directories(executable / "resources");
    int calls = 0;
    auto host = [&](const std::string &request) {
      ++calls;
      const auto options = nlohmann::json::parse(request);
      if (options.at("resources") != fs::canonical(executable / "resources").u8string())
        throw std::runtime_error("Incorrect packaged resource path");
      return nlohmann::json{{"ok", true}, {"value", options}}.dump();
    };
    const auto state = root / "new user state";
    if (!msime::windows::prepare_first_run(executable, state, host) || calls != 1 ||
        !fs::is_regular_file(state / "runtime-options.json"))
      throw std::runtime_error("First launch did not publish configuration");
    if (msime::windows::prepare_first_run(executable, state, host) || calls != 1)
      throw std::runtime_error("Second launch prepared existing state");
    fs::remove(state / "runtime-options.json");
    if (msime::windows::prepare_first_run(executable, state, host) || calls != 1)
      throw std::runtime_error("Incomplete state was rebuilt");
    std::ofstream(state / msime::windows::kDataDirectoryMarker) << "synthetic ownership";
    if (!msime::windows::prepare_first_run(executable, state, host) || calls != 2 ||
        !fs::is_regular_file(state / "runtime-options.json"))
      throw std::runtime_error("Installer-owned state was not prepared");
    fs::remove(state / "runtime-options.json");
    if (!msime::windows::prepare_first_run(executable, state, host) || calls != 3)
      throw std::runtime_error("Installer-owned state was not recoverable");
    const auto file = root / "state-file";
    std::ofstream(file) << "synthetic sentinel";
    if (msime::windows::prepare_first_run(executable, file, host) || calls != 3)
      throw std::runtime_error("Existing file was rebuilt");
    auto reject = [](const auto &action) {
      bool rejected = false;
      try { action(); } catch (...) { rejected = true; }
      if (!rejected) throw std::runtime_error("Expected refusal");
    };
    reject([&] { msime::windows::prepare_first_run(executable, "relative", host); });
    reject([&] { msime::windows::prepare_first_run(root / "missing", root / "unprepared", host); });
    if (fs::exists(root / "unprepared") || calls != 3)
      throw std::runtime_error("Missing resources mutated state");
    const auto failed = root / "failed";
    reject([&] { msime::windows::prepare_first_run(executable, failed,
        [](const std::string &) { return "{\"ok\":false}"; }); });
    if (msime::windows::prepare_first_run(executable, failed, host) || calls != 3)
      throw std::runtime_error("Failed preparation was retried destructively");
    fs::remove_all(root);
    std::cout << "Production first-run policy passed\n";
    return 0;
  } catch (...) {
    fs::remove_all(root);
    std::cerr << "Production first-run policy failed\n";
    return 1;
  }
}

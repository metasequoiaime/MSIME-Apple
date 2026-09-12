#pragma once
#include <filesystem>
#include <string>
#include <functional>
#include <thread>
#include <atomic>

namespace msime::tsf {
// Read the atomically published prepare_host document unchanged.
// The shared host validates the schema; never synthesize fallback data.
std::string read_prepared_host_options(const std::filesystem::path &file);
std::string default_host_options_json();
std::string default_state_directory();
class PreferenceWatcher final {
public:
  using Published = std::function<void(std::string)>;
  PreferenceWatcher(std::string directory, Published published);
  ~PreferenceWatcher();
  PreferenceWatcher(const PreferenceWatcher &) = delete;
  void stop() noexcept;
private:
  void run();
  std::string directory_;
  Published published_;
  std::atomic<bool> stopping_{false};
  std::thread worker_;
};
}

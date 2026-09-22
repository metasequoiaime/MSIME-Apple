#pragma once
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <mutex>
#include <string_view>

namespace msime::windows {
// The Server's diagnostic file, the counterpart of the reference's candidate_diag_log.cpp. The Server is a windows-subsystem program, so under the Watchdog nothing reads stdout or stderr; this file is where the Server log and the TIP's diagnostic batches go when the user turns on 「Server 端日志」 or 「TSF 端日志」 on the settings page.
//
// The reference writes to the Desktop and falls back to the data directory. Here the file always lives under the data directory (logs\server.log): a file that appears on the Desktop whenever a switch is on is the kind of side effect a user does not expect from an input method, and the settings page can point at the folder instead.
//
// Callers must pass state only - counts, identifiers, error codes. User input and candidate text never belong here.
class DiagnosticLog {
public:
  // Rotated to server.log.1 once it reaches this size, so at most twice this is kept.
  static constexpr std::uint64_t maximum_bytes = 4ull * 1024ull * 1024ull;

  explicit DiagnosticLog(std::filesystem::path file);

  // The two switches of DiagnosticLogPreferences. Either one opens the file.
  void set_enabled(bool server, bool tsf);
  bool server_enabled() const { return server_.load(std::memory_order_acquire); }
  bool tsf_enabled() const { return tsf_.load(std::memory_order_acquire); }

  // Appends one timestamped UTF-8 line when the server switch is on. Thread-safe; never throws.
  void server(std::string_view line);
  // Appends a TIP batch when the tsf switch is on.
  void tsf(std::string_view line);

  const std::filesystem::path &file() const { return file_; }

private:
  void append(std::string_view line);

  std::filesystem::path file_;
  std::atomic<bool> server_{false};
  std::atomic<bool> tsf_{false};
  std::mutex mutex_;
};
} // namespace msime::windows

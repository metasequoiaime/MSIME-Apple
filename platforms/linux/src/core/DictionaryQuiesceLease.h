#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <string_view>

namespace msime::linux_host {

// Dictionary maintenance (import, edit, clearing learned data) needs the Engine's exclusive lock, and every open input session holds it shared. Windows asks its server to drop the sessions for the duration (DictionaryQuiesce/DictionaryResume); on Linux the settings window writes this lease beside the lock instead, and both hosts close their sessions and open no new ones while it is live. The lease carries its own expiry, in Unix milliseconds, so a settings process that dies mid-import cannot leave input off: past the expiry, or with an expiry further out than any real lease, it is ignored. The name and the bound are shared with apps/desktop/src-tauri/src/platform/linux/linux_dictionary_quiesce.rs.
inline constexpr std::string_view kDictionaryQuiesceLeaseName = ".msime-dictionary-quiesce";
inline constexpr std::int64_t kDictionaryQuiesceLeaseMaxMs = 30'000;

inline bool dictionary_quiesce_lease_live(std::string_view contents, std::int64_t now_ms) {
  std::int64_t expiry = 0;
  bool digits = false;
  for (const char c : contents) {
    if (c == '\n') break;
    if (c < '0' || c > '9' || expiry > (INT64_MAX - 9) / 10) return false;
    expiry = expiry * 10 + (c - '0');
    digits = true;
  }
  return digits && expiry > now_ms && expiry - now_ms <= kDictionaryQuiesceLeaseMaxMs;
}

inline std::int64_t dictionary_quiesce_now_ms() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

// Called from the hosts' timers and before a session opens; a missing lease costs one failed open.
inline bool dictionary_quiesced(const std::string &user_data,
                                std::int64_t now_ms = dictionary_quiesce_now_ms()) {
  if (user_data.empty() || user_data.front() != '/') return false;
  std::ifstream lease(std::filesystem::path(user_data) / std::string(kDictionaryQuiesceLeaseName));
  if (!lease) return false;
  char buffer[32] = {};
  lease.read(buffer, sizeof buffer - 1);
  return dictionary_quiesce_lease_live(std::string_view(buffer, static_cast<std::size_t>(lease.gcount())), now_ms);
}

}  // namespace msime::linux_host

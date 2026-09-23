#pragma once

#include "../../../common/DictionaryQuiesceLease.h"

#include <string>
#include <system_error>

namespace msime::linux_host {

// The lease itself is shared with the macOS input method (platforms/common/DictionaryQuiesceLease.h); the IBus and Fcitx5 hosts reach it under their own namespace.
using msime::dictionary_lease::dictionary_quiesce_lease_live;
using msime::dictionary_lease::dictionary_quiesce_now_ms;
using msime::dictionary_lease::dictionary_quiesced;
using msime::dictionary_lease::kDictionaryQuiesceLeaseMaxMs;
using msime::dictionary_lease::kDictionaryQuiesceLeaseName;

// A menu preference save writes into the state root beside `user_data`. Moving the data directory holds the lease on that user directory while it copies, so a save waits then rather than landing in the old root after it was copied; once the move has taken the old user directory away, a host still configured for it saves nothing, so it cannot put a preferences file back into the old root. No session can open on a missing user directory either.
inline bool preference_save_held(const std::string &user_data,
                                 std::int64_t now_ms = dictionary_quiesce_now_ms()) {
  if (user_data.empty() || user_data.front() != '/') return false;
  std::error_code error;
  return !std::filesystem::is_directory(user_data, error) || dictionary_quiesced(user_data, now_ms);
}

}  // namespace msime::linux_host

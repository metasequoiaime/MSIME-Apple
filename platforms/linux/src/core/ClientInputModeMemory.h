#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

namespace msime::linux_host {

// IBus does not keep the Windows TSF client's CN/EN status for us. Keep a
// bounded in-process map keyed by the client identity supplied by IBus so
// `ime_mode_scope=app` does not leak one editor's mode into another editor.
//
// IBus only reports that identity from 1.5.27 on, and even there a client is
// free to stay anonymous. Windows always has a TSF client to hang the mode on,
// so the nearest equivalent for an anonymous client is one shared slot: every
// window that cannot be told apart is treated as the same one. Dropping the
// mode instead would send the user back to the configured default every time
// focus left and came back, which no other platform does.
class ClientInputModeMemory {
public:
  static constexpr std::size_t kMaxClients = 128;

  void remember(std::string_view client, bool enabled) {
    if (client.empty()) {
      anonymous_ = enabled;
      return;
    }
    const std::string key(client);
    if (modes_.find(key) == modes_.end() && modes_.size() >= kMaxClients)
      modes_.clear();
    modes_[key] = enabled;
  }

  bool knows(std::string_view client) const {
    if (client.empty())
      return anonymous_.has_value();
    return modes_.find(std::string(client)) != modes_.end();
  }

  bool restore(std::string_view client, bool fallback) const {
    if (client.empty())
      return anonymous_.value_or(fallback);
    const auto found = modes_.find(std::string(client));
    return found == modes_.end() ? fallback : found->second;
  }

  void clear() {
    modes_.clear();
    anonymous_.reset();
  }

private:
  std::unordered_map<std::string, bool> modes_;
  std::optional<bool> anonymous_;
};

} // namespace msime::linux_host

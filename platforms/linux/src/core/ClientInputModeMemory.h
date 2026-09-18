#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <unordered_map>

namespace msime::linux_host {

// IBus does not keep the Windows TSF client's CN/EN status for us. Keep a
// bounded in-process map keyed by the client identity supplied by IBus so
// `ime_mode_scope=app` does not leak one editor's mode into another editor.
class ClientInputModeMemory {
public:
  static constexpr std::size_t kMaxClients = 128;

  void remember(std::string_view client, bool enabled) {
    if (client.empty())
      return;
    const std::string key(client);
    if (modes_.find(key) == modes_.end() && modes_.size() >= kMaxClients)
      modes_.clear();
    modes_[key] = enabled;
  }

  bool restore(std::string_view client, bool fallback) const {
    if (client.empty())
      return fallback;
    const auto found = modes_.find(std::string(client));
    return found == modes_.end() ? fallback : found->second;
  }

  void clear() { modes_.clear(); }

private:
  std::unordered_map<std::string, bool> modes_;
};

} // namespace msime::linux_host

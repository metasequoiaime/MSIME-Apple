#pragma once
#include "NavigationPolicy.h"
#include "WordCharacterPolicy.h"
#include "windows_ipc.h"
#include <nlohmann/json.hpp>
#include <string>
#include <thread>

namespace msime::windows {
struct KeyResult {
  uint64_t client_id;
  uint64_t activation_epoch;
  uint64_t request_id;
  bool reply_expected;
  nlohmann::json transition;
};
struct NavigationResult {
  KeyResult key;
  NavigationReply direction;
};
struct WordCharacterResult {
  KeyResult key;
  bool exact;
};

// Lives on the Server input queue, never inside the injected TSF DLL. The pipe
// router authenticates/negotiates a client before constructing its session, and
// assigns monotonically increasing focus epochs. This class is not a pipe
// server.
class ServerSession final {
public:
  ServerSession(uint64_t client_id, const std::string &prepared_options);
  ~ServerSession();
  ServerSession(const ServerSession &) = delete;
  ServerSession &operator=(const ServerSession &) = delete;
  nlohmann::json activate(uint64_t epoch);
  nlohmann::json deactivate(uint64_t epoch);
  void cancel_composition(uint64_t epoch);
  void set_input_enabled(uint64_t epoch, bool enabled);
  void set_chinese_punctuation(uint64_t epoch, bool enabled);
  bool input_enabled() const {
    check_thread();
    return input_enabled_;
  }
  KeyResult key(const FanyImeNamedpipeData &packet, uint64_t epoch);
  KeyResult punctuation(const FanyImeNamedpipeData &packet, uint64_t epoch);
  std::optional<WordCharacterResult>
  word_character(const FanyImeNamedpipeData &packet, uint64_t epoch,
                 WordCharacterBinding binding);
  std::optional<NavigationResult> navigate(const FanyImeNamedpipeData &packet,
                                           uint64_t epoch,
                                           const NavigationBindings &bindings);
  nlohmann::json select(uint64_t epoch, uint64_t generation, size_t index);
  std::optional<std::string> online_query(uint64_t epoch);
  std::optional<nlohmann::json>
  apply_cloud_response(uint64_t epoch, const std::string &query,
                       const std::string &body);
  nlohmann::json update_preferences(uint64_t epoch,
                                    const std::string &snapshot);
  nlohmann::json view() const;

private:
  void check_thread() const;
  void check_active(uint64_t epoch) const;
  const std::thread::id thread_ = std::this_thread::get_id();
  uint64_t client_;
  uint64_t session_ = 0;
  uint64_t epoch_ = 0;
  bool active_ = false;
  bool input_enabled_ = true;
};
} // namespace msime::windows

#pragma once

#include "FocusGate.h"

#include <atomic>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace msime::windows {
// Requests AI 联想 candidates away from the input queue.
//
// Everything below this worker already existed - msime_client_ai_http_request,
// msime_client_parse_ai_response and msime_client_apply_online_candidates are
// exported, and the online query already carries the resolved ai_assistant
// config and an ai_eligible flag - but nothing on Windows ever called them, so
// turning AI 辅助 on in settings changed nothing and no AI candidate appeared.
class AiCandidateWorker final {
public:
  struct Result {
    FocusLease lease;
    // The query this answers, so a stale reply can be recognised.
    std::string query;
    std::vector<std::string> candidates;
  };
  using Completed = std::function<void(Result)>;

  explicit AiCandidateWorker(Completed completed);
  ~AiCandidateWorker();
  AiCandidateWorker(const AiCandidateWorker &) = delete;
  AiCandidateWorker &operator=(const AiCandidateWorker &) = delete;

  // Keeps only the newest request; never waits for a response.
  bool submit(const FocusLease &lease, std::string query);
  void request_stop();
  void stop();
  bool failed() const { return failed_.load(std::memory_order_acquire); }

private:
  struct Request {
    FocusLease lease;
    std::string query;
    uint64_t serial = 0;
  };
  void run();
  bool cancelled(uint64_t serial) const noexcept;
  std::vector<std::string> fetch(const std::string &query,
                                 const std::function<bool()> &cancelled);

  Completed completed_;
  std::mutex mutex_;
  std::mutex join_mutex_;
  std::condition_variable wake_;
  std::optional<Request> pending_;
  uint64_t next_serial_ = 0;
  std::atomic<uint64_t> latest_serial_{0};
  std::atomic<bool> stopping_{false};
  std::atomic<bool> failed_{false};
  // Successful results are reusable across candidate generations. The key is
  // derived from provider identity and pinyin segments, never credentials.
  std::unordered_map<std::string, std::vector<std::string>> candidate_cache_;
  std::thread worker_;
};
} // namespace msime::windows

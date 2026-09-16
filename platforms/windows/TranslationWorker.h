#pragma once

#include "FocusGate.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>

namespace msime::windows {
class TranslationWorker final {
public:
  struct Result {
    FocusLease lease;
    uint64_t generation = 0;
    std::string translations;
  };
  using Completed = std::function<void(Result)>;

  explicit TranslationWorker(Completed completed);
  ~TranslationWorker();
  TranslationWorker(const TranslationWorker &) = delete;
  TranslationWorker &operator=(const TranslationWorker &) = delete;

  bool submit(const FocusLease &lease, std::string query);
  void request_stop();
  void stop();

private:
  struct Request {
    FocusLease lease;
    std::string query;
    uint64_t serial = 0;
  };

  void run() noexcept;
  bool cancelled(uint64_t serial) const noexcept;
  std::optional<Result> translate(const Request &request,
                                  const std::function<bool()> &cancelled);

  Completed completed_;
  mutable std::mutex mutex_;
  std::condition_variable wake_;
  std::optional<Request> pending_;
  uint64_t next_serial_ = 0;
  std::atomic<uint64_t> latest_serial_{0};
  std::atomic<bool> stopping_{false};
  std::mutex join_mutex_;
  // Results are reusable across generations. Keys include provider scope,
  // target language, direction, and source/target items, but no credentials.
  std::unordered_map<std::string, std::string> translation_cache_;
  std::unordered_map<std::string, std::chrono::steady_clock::time_point>
      translation_negative_cache_;
  std::thread worker_;
};
} // namespace msime::windows

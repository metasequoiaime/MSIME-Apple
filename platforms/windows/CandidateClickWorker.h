#pragma once
#include "CandidatePresentation.h"
#include <atomic>
#include <condition_variable>
#include <functional>
#include <thread>

namespace msime::windows {
struct CandidateClick {
  FocusLease lease;
  uint64_t session, generation;
  size_t index;
};
// One worker and one outstanding click. No backlog/retries. Dependencies must
// outlive stop(); cancel handler I/O before joining when necessary.
class CandidateClickWorker final {
public:
  using Handler = std::function<void(const CandidateClick &)>;
  explicit CandidateClickWorker(Handler handler)
      : handler_(std::move(handler)) {
    if (!handler_)
      throw std::invalid_argument("Missing click handler");
    worker_ = std::thread([this] { run(); });
  }
  ~CandidateClickWorker() { stop(); }
  CandidateClickWorker(const CandidateClickWorker &) = delete;
  CandidateClickWorker &operator=(const CandidateClickWorker &) = delete;
  bool submit(const CandidateClick &click) {
    // Handler/I/O never holds this short state lock.
    std::lock_guard lock(mutex_);
    if (stopping_ || busy_)
      return false;
    pending_ = click;
    busy_ = true;
    ready_.notify_one();
    return true;
  }
  void request_stop() {
    std::lock_guard lock(mutex_);
    stopping_ = true;
    pending_.reset();
    ready_.notify_all();
  }
  void stop() {
    request_stop();
    if (worker_.joinable())
      worker_.join();
  }
  bool failed() const { return failed_.load(); }

private:
  void run() noexcept {
    for (;;) {
      std::optional<CandidateClick> click;
      {
        std::unique_lock lock(mutex_);
        ready_.wait(lock, [&] { return stopping_ || pending_.has_value(); });
        if (stopping_)
          return;
        click = std::move(pending_);
        pending_.reset();
      }
      try {
        handler_(*click);
      } catch (...) {
        failed_ = true;
        request_stop();
        return;
      }
      std::lock_guard lock(mutex_);
      busy_ = false;
    }
  }
  Handler handler_;
  std::mutex mutex_;
  std::condition_variable ready_;
  std::optional<CandidateClick> pending_;
  bool stopping_ = false, busy_ = false;
  std::atomic<bool> failed_{false};
  std::thread worker_;
};
} // namespace msime::windows

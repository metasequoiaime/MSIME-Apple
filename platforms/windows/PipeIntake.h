#pragma once
#include "PipeRegistry.h"
#include <condition_variable>
#include <deque>
#include <functional>
#include <thread>

namespace msime::windows {
struct IntakeStats {
  size_t queued = 0;
  size_t active = 0;
  uint64_t rejected = 0;
  uint64_t failed = 0;
};
// Fixed-size handshake workers. submit always consumes the connection, closing
// it on rejection. Registered input loops do not run on these workers.
class PipeIntake final {
public:
  // Completion runs on a worker and must be short/nonblocking. Return false if
  // the downstream bounded queue cannot accept the registration: it is removed.
  // Never call stop/destruct this object from completion. Registry and captured
  // callback state must outlive stop(), which joins all workers.
  using Completion = std::function<bool(uint32_t, const PipeRegistration &)>;
  PipeIntake(PipeRegistry &registry, size_t workers, size_t queue_capacity,
             uint32_t capabilities, DWORD timeout_ms, Completion completion);
  ~PipeIntake();
  PipeIntake(const PipeIntake &) = delete;
  PipeIntake &operator=(const PipeIntake &) = delete;
  bool submit(std::unique_ptr<PipeConnection> connection, uint32_t role);
  void
  stop(); // Control thread only; cancels handshakes, discards queue, joins.
  IntakeStats stats() const;

private:
  struct Job {
    std::unique_ptr<PipeConnection> connection;
    uint32_t role;
  };
  void run();
  PipeRegistration handshake(Job job);
  PipeRegistry &registry_;
  size_t capacity_;
  uint32_t capabilities_;
  DWORD timeout_;
  Completion completion_;
  HANDLE cancel_ = nullptr;
  mutable std::mutex mutex_;
  std::mutex stop_mutex_;
  std::condition_variable ready_;
  bool stopping_ = false;
  std::deque<Job> queue_;
  std::vector<std::thread> workers_;
  IntakeStats stats_;
};
} // namespace msime::windows

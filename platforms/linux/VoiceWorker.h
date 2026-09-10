#pragma once
#include <atomic>
#include <functional>
#include <string>
#include <thread>

// Host-owned worker. Capture/provider code is injected by run(); the worker
// guarantees cancellation before destruction and never invokes callbacks after
// cancellation has been observed.
class MsimeVoiceWorker {
 public:
  using Task = std::function<std::string(const std::atomic_bool &)>;
  using Result = std::function<void(std::string)>;
  ~MsimeVoiceWorker() { cancel(); }
  MsimeVoiceWorker(const MsimeVoiceWorker &) = delete;
  void cancel() {
    cancelled_.store(true);
    if (thread_.joinable()) thread_.join();
  }
  void run(Task task, Result result) {
    cancel();
    cancelled_.store(false);
    thread_ = std::thread([this, task = std::move(task), result = std::move(result)] {
      auto value = task(cancelled_);
      if (!cancelled_.load() && result) result(std::move(value));
    });
  }
 private:
  std::atomic_bool cancelled_{false};
  std::thread thread_;
};

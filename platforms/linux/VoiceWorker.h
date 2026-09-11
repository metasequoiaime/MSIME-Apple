#pragma once
#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <thread>

// Host-owned worker. Capture/provider code is injected by run(); the worker
// guarantees cancellation before destruction and never invokes callbacks after
// cancellation has been observed.
class MsimeVoiceWorker {
 public:
  using Task = std::function<std::string(const std::atomic_bool &)>;
  using Result = std::function<void(std::string)>;
  MsimeVoiceWorker() : cancelled_(std::make_shared<std::atomic_bool>(false)) {}
  ~MsimeVoiceWorker() { cancel(); }
  MsimeVoiceWorker(const MsimeVoiceWorker &) = delete;
  void cancel() {
    cancelled_->store(true);
    if (thread_.joinable()) thread_.join();
  }
  // Stop accepting a result without waiting for a provider socket. The
  // detached task owns its cancellation token and never dereferences this
  // worker after the handoff.
  void cancel_async() {
    cancelled_->store(true);
    if (thread_.joinable()) thread_.detach();
  }
  void run(Task task, Result result) {
    cancel();
    cancelled_ = std::make_shared<std::atomic_bool>(false);
    const auto token = cancelled_;
    thread_ = std::thread([token, task = std::move(task), result = std::move(result)] {
      auto value = task(*token);
      if (!token->load() && result) result(std::move(value));
    });
  }
 private:
  std::shared_ptr<std::atomic_bool> cancelled_;
  std::thread thread_;
};

#pragma once
#include "PreferenceMonitor.h"
#include "RegistrationInbox.h"
#include "SessionWorkers.h"
#include <atomic>

namespace msime::windows {
enum class ControllerFailure {
  None,
  Service,
  InputQueue,
  SessionWorkers,
  Control,
  Preferences
};
// Owns the queue, connection workers and their external supervision thread.
// Service and mailbox are constructed first and must outlive this controller.
// stop_service runs once on the control thread and must close ALL registered
// endpoints (including unconsumed inbox tickets) and join service workers.
class SessionController final {
public:
  SessionController(
      MainTransport &transport, RegistrationInbox &inbox, size_t clients,
      size_t input_capacity, std::string options, SessionPump::KeyHandler key,
      SessionPump::EventHandler event, std::function<bool()> healthy,
      std::function<void()> stop_service,
      std::chrono::milliseconds interval = std::chrono::milliseconds(100),
      std::string preferences_directory = {});
  ~SessionController();
  SessionController(const SessionController &) = delete;
  SessionController &operator=(const SessionController &) = delete;
  void request_stop(); // Callback-safe: only signals/closes the mailbox.
  void
  stop(); // External thread, waits for ordered service/worker/queue shutdown.
  ControllerFailure failure() const { return failure_.load(); }
  std::optional<PreferenceMonitorStatus> preferences_status() const {
    return preferences_
               ? std::optional<PreferenceMonitorStatus>(preferences_->status())
               : std::nullopt;
  }

private:
  void run();
  RegistrationInbox &inbox_;
  std::function<bool()> healthy_;
  std::function<void()> stop_service_;
  std::chrono::milliseconds interval_;
  FocusGate focus_;
  InputQueue input_;
  SessionWorkers workers_;
  std::unique_ptr<PreferenceMonitor> preferences_;
  std::atomic<bool> stopping_{false};
  std::atomic<ControllerFailure> failure_{ControllerFailure::None};
  std::mutex stop_mutex_;
  std::thread control_;
};
} // namespace msime::windows

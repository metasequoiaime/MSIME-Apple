#include "SessionController.h"

namespace msime::windows {
namespace {
thread_local const SessionController *active_controller = nullptr;
}
SessionController::SessionController(
    MainTransport &transport, RegistrationInbox &inbox, size_t clients,
    size_t input_capacity, std::string options, SessionPump::KeyHandler key,
    SessionPump::EventHandler event, std::function<bool()> healthy,
    std::function<void()> stop_service, std::chrono::milliseconds interval,
    std::string preferences_directory, SessionPump::Presentation presentation)
    : inbox_(inbox), transport_(transport), healthy_(std::move(healthy)),
      stop_service_(std::move(stop_service)), interval_(interval),
      input_(focus_, clients, input_capacity, std::move(options)),
      workers_(transport, input_, focus_, clients, std::move(key),
               std::move(event), std::move(presentation)) {
  if (!healthy_ || !stop_service_ || interval.count() < 1 ||
      interval.count() > 1000)
    throw std::invalid_argument("Invalid session supervision configuration");
  if (!preferences_directory.empty())
    preferences_ = std::make_unique<PreferenceMonitor>(
        input_, std::move(preferences_directory));
  control_ = std::thread(&SessionController::run, this);
}
SessionController::~SessionController() { stop(); }
ModeRequestResult SessionController::request_mode(const FocusLease &lease,
                                                 WorkerMode mode) {
  if (input_.on_worker_thread() || active_controller == this)
    throw std::logic_error("Mode request cannot reenter controller callbacks");
  const auto bytes = worker_mode_bytes(mode);
  if (!bytes || stopping_)
    return ModeRequestResult::Rejected;
  bool attempted = false;
  bool sent = false;
  try {
    focus_.with_active(lease, [&] {
      if (stopping_ || !transport_.current(lease.transport))
        return;
      attempted = true;
      sent = transport_.send(lease.transport,
                             FanyImePipeRole::ToTsfWorkerThread, *bytes);
    });
  } catch (...) {
    // A throwing transport is also uncertain; never retry the mode command.
    attempted = true;
  }
  if (!attempted)
    return ModeRequestResult::Rejected;
  if (sent)
    return ModeRequestResult::Sent;
  focus_.invalidate(lease.transport);
  transport_.close(lease.transport);
  return ModeRequestResult::WriteFailed;
}
void SessionController::request_stop() {
  stopping_ = true;
  inbox_.close();
}
void SessionController::stop() {
  if (input_.on_worker_thread() || active_controller == this)
    throw std::logic_error("Controller cannot join a dependent thread");
  std::lock_guard lock(stop_mutex_);
  request_stop();
  if (control_.joinable())
    control_.join();
}
void SessionController::run() {
  active_controller = this;
  try {
    while (!stopping_) {
      auto ticket = inbox_.take_for(interval_);
      if (stopping_ || inbox_.closed())
        break;
      if (!healthy_()) {
        failure_ = ControllerFailure::Service;
        break;
      }
      if (!input_.stats().accepting) {
        failure_ = ControllerFailure::InputQueue;
        break;
      }
      if (workers_.stats().stopping) {
        failure_ = ControllerFailure::SessionWorkers;
        break;
      }
      if (preferences_ && preferences_->failed()) {
        failure_ = ControllerFailure::Preferences;
        break;
      }
      if (ticket)
        workers_.submit(*ticket);
    }
  } catch (...) {
    failure_ = ControllerFailure::Control;
  }
  request_stop();
  if (preferences_)
    preferences_->request_stop();
  // Stop intake/listeners and cancel registry reads first. The queue remains
  // live while pumps submit their final session cleanup. Input/handshake
  // callbacks never join.
  try {
    stop_service_();
  } catch (...) {
    failure_ = ControllerFailure::Control;
  }
  workers_.stop();
  input_.stop();
  if (preferences_)
    preferences_->stop();
  active_controller = nullptr;
}
} // namespace msime::windows

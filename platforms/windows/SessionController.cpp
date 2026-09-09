#include "SessionController.h"

namespace msime::windows {
namespace {
thread_local const SessionController *active_controller = nullptr;
}
SessionController::SessionController(
    MainTransport &transport, RegistrationInbox &inbox, size_t clients,
    size_t input_capacity, std::string options, SessionPump::KeyHandler key,
    SessionPump::EventHandler event, std::function<bool()> healthy,
    std::function<void()> stop_service, std::chrono::milliseconds interval)
    : inbox_(inbox), healthy_(std::move(healthy)),
      stop_service_(std::move(stop_service)), interval_(interval),
      input_(focus_, clients, input_capacity, std::move(options)),
      workers_(transport, input_, focus_, clients, std::move(key),
               std::move(event)) {
  if (!healthy_ || !stop_service_ || interval.count() < 1 ||
      interval.count() > 1000)
    throw std::invalid_argument("Invalid session supervision configuration");
  control_ = std::thread(&SessionController::run, this);
}
SessionController::~SessionController() { stop(); }
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
      if (ticket)
        workers_.submit(*ticket);
    }
  } catch (...) {
    failure_ = ControllerFailure::Control;
  }
  request_stop();
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
  active_controller = nullptr;
}
} // namespace msime::windows

#include "SessionController.h"
#include "UiSelectionDelivery.h"

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
      presentation_(std::move(presentation)), event_(std::move(event)),
      input_(focus_, clients, input_capacity, std::move(options)),
      workers_(
          transport, input_, focus_, clients, std::move(key),
          [this](const FocusRoute &route, const FanyImeNamedpipeData &packet) {
            if (route.route)
              candidates_.event(*route.route, packet);
            return event_(route, packet);
          },
          {[this](const FocusLease &lease, const PendingReply &reply,
                  const FanyImeNamedpipeData &packet) {
             candidates_.delivered(lease, reply, packet);
             if (presentation_.delivered)
               presentation_.delivered(lease, reply, packet);
           },
           [this](const PipeTicket &ticket) {
             candidates_.disconnected(ticket);
             if (presentation_.disconnected)
               presentation_.disconnected(ticket);
           }},
          transactions_) {
  if (!event_ || !healthy_ || !stop_service_ || interval.count() < 1 ||
      interval.count() > 1000)
    throw std::invalid_argument("Invalid session supervision configuration");
  if (!preferences_directory.empty())
    preferences_ = std::make_unique<PreferenceMonitor>(
        input_, std::move(preferences_directory));
  control_ = std::thread(&SessionController::run, this);
}
SessionController::~SessionController() { stop(); }
SelectionRequestResult
SessionController::request_selection(const FocusLease &lease, uint64_t session,
                                     uint64_t generation, size_t index) {
  if (input_.on_worker_thread() || active_controller == this)
    throw std::logic_error("Selection cannot reenter controller callbacks");
  std::unique_lock transaction(*transactions_, std::try_to_lock);
  if (!transaction.owns_lock())
    return SelectionRequestResult::Busy;
  const auto fail = [&] {
    focus_.invalidate(lease.transport);
    transport_.close(lease.transport);
    failure_ = ControllerFailure::Control;
    request_stop();
    return SelectionRequestResult::Failed;
  };
  try {
    const auto shown = candidate_view();
    if (!shown || !shown->visible || shown->session != session ||
        shown->generation != generation || shown->lease.epoch != lease.epoch ||
        shown->lease.token != lease.token ||
        !same_ticket(shown->lease.transport, lease.transport))
      return SelectionRequestResult::Rejected;
    bool found = false;
    for (const auto &candidate : shown->candidates)
      if (candidate.index == index && candidate.session == session &&
          candidate.generation == generation)
        found = true;
    if (!found)
      return SelectionRequestResult::Rejected;
    std::optional<PendingReply> pending;
    auto prepared = input_.submit([&](InputState &state) {
      if (!stopping_ && transport_.current(lease.transport))
        pending = state.select_candidate(lease, session, generation, index);
    });
    if (!prepared || prepared->get() != InputTaskStatus::Completed)
      return fail();
    if (!pending)
      return SelectionRequestResult::Rejected;
    if (!pending->ui_selection || stopping_ ||
        deliver_ui_selection(transport_, focus_, lease,
                             *pending->ui_selection) != UiDeliveryResult::Sent)
      return fail();
    bool delivered = false;
    auto confirmed = input_.submit([&](InputState &state) {
      if (stopping_)
        return;
      delivered = state.ui_delivered(
          lease, pending->source.transition.at("view").at("generation"));
      if (delivered) {
        const bool active = focus_.with_active(lease, [&] {
          if (!transport_.current(lease.transport)) {
            delivered = false;
            return;
          }
          // UI has no key packet. Preserve the last confirmed screen anchor;
          // id zero and ui_selection distinguish this callback from key input.
          FanyImeNamedpipeData packet{};
          packet.client_id = lease.transport.client;
          packet.event_type = FanyImePipeEventType::KeyEvent;
          packet.point[0] = shown->x;
          packet.point[1] = shown->y;
          candidates_.delivered(lease, *pending, packet);
          if (presentation_.delivered)
            presentation_.delivered(lease, *pending, packet);
        });
        delivered = delivered && active;
      }
    });
    if (!confirmed || confirmed->get() != InputTaskStatus::Completed ||
        !delivered)
      return fail();
    return SelectionRequestResult::Sent;
  } catch (...) {
    return fail();
  }
}
std::optional<CandidatePresentation> SessionController::candidate_view() {
  if (input_.on_worker_thread() || active_controller == this)
    throw std::logic_error(
        "Candidate read cannot reenter controller callbacks");
  if (stopping_ || !input_.stats().accepting)
    return std::nullopt;
  auto value = candidates_.snapshot(focus_, false, [&](const FocusLease &lease) {
    return transport_.try_current(lease.transport);
  });
  if (stopping_ || !input_.stats().accepting)
    return std::nullopt;
  return value;
}
ModeRequestResult SessionController::request_mode(const FocusLease &lease,
                                                  WorkerMode mode) {
  if (input_.on_worker_thread() || active_controller == this)
    throw std::logic_error("Mode request cannot reenter controller callbacks");
  const auto bytes = worker_mode_bytes(mode);
  if (!bytes || stopping_)
    return ModeRequestResult::Rejected;
  std::unique_lock transaction(*transactions_, std::try_to_lock);
  if (!transaction.owns_lock())
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
  candidates_.stop();
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

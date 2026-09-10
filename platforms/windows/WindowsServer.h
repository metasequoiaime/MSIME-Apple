#pragma once
#include "PipeMainTransport.h"
#include "PipeService.h"
#include "SessionController.h"

namespace msime::windows {
struct WindowsServerOptions {
  PipeServiceOptions pipes; // Explicit names/capabilities, no product defaults.
  size_t registration_capacity = 64;
  size_t input_capacity = 256;
  DWORD write_timeout = 250;
  std::string
      preferences_directory; // Explicit shared store; empty disables polling.
  PreferenceMonitor::Published preferences_published;
};
// Starts an actual native service when constructed. The caller must explicitly
// choose names and implement native key/UI behavior; this never registers TSF.
// Callbacks may run before construction returns; captured dependencies must
// already exist, and must not access this server until construction completes.
class WindowsServer final {
public:
  WindowsServer(WindowsServerOptions options, std::string host_options,
                SessionPump::KeyHandler key, SessionPump::EventHandler event,
                SessionPump::Presentation presentation = {});
  ~WindowsServer();
  WindowsServer(const WindowsServer &) = delete;
  WindowsServer &operator=(const WindowsServer &) = delete;
  void request_stop() { controller_->request_stop(); }
  void stop() { controller_->stop(); }
  ControllerFailure failure() const { return controller_->failure(); }
  std::optional<CandidatePresentation> candidate_view() {
    return controller_->candidate_view();
  }
  std::optional<ModePresentation> mode_view() { return controller_->mode_view(); }
  SelectionRequestResult request_selection(const FocusLease &lease,
      uint64_t session, uint64_t generation, size_t index) {
    return controller_->request_selection(lease, session, generation, index);
  }
  ModeRequestResult request_mode(const FocusLease &lease, WorkerMode mode) {
    return controller_->request_mode(lease, mode);
  }
  std::optional<PreferenceMonitorStatus> preferences_status() const {
    return controller_->preferences_status();
  }

private:
  RegistrationInbox inbox_;
  std::unique_ptr<PipeService> service_;
  std::unique_ptr<PipeMainTransport> transport_;
  std::unique_ptr<SessionController> controller_;
};
} // namespace msime::windows

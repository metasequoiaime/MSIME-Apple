#pragma once
#include "AuxPipeService.h"
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
  std::wstring aux_pipe_name; // Empty disables the session-less host-action pipe.
  AuxPipeService::Message aux_message;
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
  void request_stop();
  void stop();
  ControllerFailure failure() const { return controller_->failure(); }
  std::optional<CandidatePresentation> candidate_view() {
    return controller_->candidate_view();
  }
  std::optional<ModePresentation> mode_view() { return controller_->mode_view(); }
  SelectionRequestResult request_selection(const FocusLease &lease,
      uint64_t session, uint64_t generation, size_t index) {
    return controller_->request_selection(lease, session, generation, index);
  }
  CandidateActionRequestResult request_candidate_action(
      const FocusLease &lease, uint64_t session, uint64_t generation,
      size_t index, CandidateAction action, uint8_t position = 0) {
    return controller_->request_candidate_action(lease, session, generation,
                                                 index, action, position);
  }
  CandidatePageRequestResult request_page(const CandidatePage &page) {
    return controller_->request_page(page);
  }
  ModeRequestResult request_mode(const FocusLease &lease, WorkerMode mode) {
    return controller_->request_mode(lease, mode);
  }
  VoiceCompositionResult send_voice_composition(
      const FocusLease &lease, uint32_t message, std::wstring_view text,
      wchar_t generation) {
    return controller_->send_voice_composition(lease, message, text, generation);
  }
  std::optional<PreferenceMonitorStatus> preferences_status() const {
    return controller_->preferences_status();
  }

private:
  RegistrationInbox inbox_;
  std::unique_ptr<PipeService> service_;
  std::unique_ptr<PipeMainTransport> transport_;
  std::unique_ptr<SessionController> controller_;
  std::unique_ptr<AuxPipeService> aux_;
};
} // namespace msime::windows

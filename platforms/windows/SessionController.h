#pragma once
#include "CandidateAction.h"
#include "CandidateClickWorker.h"
#include "ModeMailbox.h"
#include "CandidateMailbox.h"
#include "CloudCandidateWorker.h"
#include "TranslationWorker.h"
#include "PreferenceMonitor.h"
#include "RegistrationInbox.h"
#include "SessionWorkers.h"
#include <atomic>
#include <string_view>

namespace msime::windows {
enum class ModeRequestResult { Rejected, Sent, WriteFailed };
enum class SelectionRequestResult { Rejected, Busy, Sent, Failed };
enum class CandidateActionRequestResult { Rejected, Busy, Sent, Failed };
enum class CandidatePageRequestResult { Rejected, Busy, Sent, Failed };
enum class VoiceCompositionResult { Rejected, Busy, Sent, Failed };
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
      std::string preferences_directory = {},
      SessionPump::Presentation presentation = {},
      PreferenceMonitor::Published published = {});
  ~SessionController();
  SessionController(const SessionController &) = delete;
  SessionController &operator=(const SessionController &) = delete;
  void request_stop(); // Callback-safe: only signals/closes the mailbox.
  void
  stop(); // External thread, waits for ordered service/worker/queue shutdown.
  ControllerFailure failure() const { return failure_.load(); }
  // External thread only; finite transport write may block. Sent means bytes
  // delivered, not that TSF applied the mode. Never call from input/event callbacks.
  ModeRequestResult request_mode(const FocusLease &lease, WorkerMode mode);
  // Push the TSF-local settings to the focused TIP. Returns true only when
  // every frame was accepted.
  bool send_tsf_config(const FocusLease &lease, const TsfLocalConfig &config);
  bool send_caps_lock(const FocusLease &lease, bool enabled);
  // External/UI thread, value copy only. Empty means hide. Re-read on paint;
  // selection still requires an independently validated candidate command.
  std::optional<CandidatePresentation> candidate_view();
  std::optional<ModePresentation> mode_view();
  // External I/O thread only, never a window/input callback. Busy is a dropped
  // request, not queued/replayed. Sent means delivery confirmed, not TSF applied.
  SelectionRequestResult request_selection(const FocusLease &lease,
      uint64_t session, uint64_t generation, size_t index);
  CandidateActionRequestResult request_candidate_action(
      const FocusLease &lease, uint64_t session, uint64_t generation,
      size_t index, CandidateAction action, uint8_t position = 0);
  CandidatePageRequestResult request_page(const CandidatePage &page);
  // Send a bounded voice snapshot through the authenticated worker endpoint.
  // The caller owns recording/ASR; this method only validates the focus lease
  // and performs the ordered frame delivery.
  VoiceCompositionResult send_voice_composition(
      const FocusLease &lease, uint32_t message, std::wstring_view text,
      wchar_t generation);
  std::optional<PreferenceMonitorStatus> preferences_status() const {
    return preferences_
               ? std::optional<PreferenceMonitorStatus>(preferences_->status())
               : std::nullopt;
  }

private:
  void run();
  RegistrationInbox &inbox_;
  MainTransport &transport_;
  std::function<bool()> healthy_;
  std::function<void()> stop_service_;
  std::chrono::milliseconds interval_;
  FocusGate focus_;
  CandidateMailbox candidates_;
  ModeMailbox modes_;
  std::shared_ptr<std::mutex> transactions_ = std::make_shared<std::mutex>();
  SessionPump::Presentation presentation_;
  SessionPump::EventHandler event_;
  InputQueue input_;
  CloudCandidateWorker cloud_;
  TranslationWorker translations_;
  SessionWorkers workers_;
  std::unique_ptr<PreferenceMonitor> preferences_;
  std::atomic<bool> stopping_{false};
  std::atomic<ControllerFailure> failure_{ControllerFailure::None};
  std::mutex stop_mutex_;
  std::thread control_;
};
} // namespace msime::windows

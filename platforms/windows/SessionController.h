#pragma once
#include "CandidateAction.h"
#include "CandidateClickWorker.h"
#include "ModeMailbox.h"
#include "CandidateMailbox.h"
#include "CloudCandidateWorker.h"
#include "AiCandidateWorker.h"
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
  bool send_caps_lock(const FocusLease &lease, bool enabled);
  // Push the TSF-local settings to every registered TIP. Returns true only
  // when every snapshot ticket accepted the complete frame set.
  bool send_tsf_config(const TsfLocalConfig &config);
  // External/UI thread, value copy only. Empty means hide. Re-read on paint;
  // selection still requires an independently validated candidate command.
  std::optional<CandidatePresentation> candidate_view();
  void wait_candidate_render_for_key(const FocusLease &lease,
                                     const FanyImeNamedpipeData &packet);
  // Called after the native candidate window has successfully presented a
  // frame. The receipt is generation- and lease-bound.
  void candidate_rendered(const FocusLease &lease, uint64_t generation) {
    candidates_.rendered(lease, generation);
  }
  std::optional<ModePresentation> mode_view();
  // Definitive: is a focused client's mode on file at all. mode_view() returns
  // nothing for contention as well, so a UI needs this to tell busy from gone.
  bool mode_active();
  // External worker only: reads Engine state on its owning input queue.
  // Empty means stale, busy or unavailable; never a guessed mode.
  std::optional<bool> dedicated_english_state(const FocusLease &lease);
  // Exit the Engine's dedicated-English mode for this exact focus lease.
  bool exit_dedicated_english(const FocusLease &lease);
  // Control-thread lease validation, not a best-effort UI snapshot. Waits for
  // an existing focus transaction instead of treating a busy gate as loss.
  bool focus_current(const FocusLease &lease);
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
  // The Aux pipe's TerminalDeactivation fallback. Called on the Aux listener
  // thread, never from an input or window callback. Returns true only once the
  // named client really is not focused under that token, because the DLL
  // writes its "OK" on the strength of this answer.
  bool deactivate_terminal(uint64_t client, uint64_t token);
  // Release every Engine session so another process can take the exclusive
  // dictionary lock, and rebuild them afterwards. Called on the Aux listener
  // thread. A quiesce that is never resumed would leave the IME dead, so it
  // carries its own deadline and the control loop resumes without being
  // asked once it passes.
  bool quiesce_dictionaries();
  bool resume_dictionaries();
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
  AiCandidateWorker ai_;
  TranslationWorker translations_;
  SessionWorkers workers_;
  std::unique_ptr<PreferenceMonitor> preferences_;
  std::atomic<bool> stopping_{false};
  // Monotonic deadline for an outstanding quiesce; zero when not quiesced.
  std::atomic<std::chrono::steady_clock::rep> quiesce_deadline_{0};
  std::atomic<ControllerFailure> failure_{ControllerFailure::None};
  std::mutex stop_mutex_;
  std::thread control_;
};
} // namespace msime::windows

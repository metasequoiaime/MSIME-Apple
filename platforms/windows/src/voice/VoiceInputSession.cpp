#include "VoiceInputSession.h"
#include "PolishPrompt.h"

#include "ReplyCodec.h"
#include "SystemAudioMuter.h"
#include "VoiceProviders.h"
#include "VoiceSessionPolicy.h"
#include <msime/voice/audio_capture.h>
#include <msime/voice/cloud_stt_worker.h>
#include <msime/voice/provider_protocol.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstring>
#include <type_traits>

namespace msime::windows {
namespace {
constexpr std::size_t kSampleRate = 16000;
// MSIME-Windows keeps its message boxes until they are dismissed. The overlay cannot take focus, so it holds a failure long enough to read a provider's sentence and then steps aside.
constexpr DWORD kFailureDisplayMs = 4000;
constexpr DWORD kFailurePollMs = 100;

std::wstring wide(std::string_view text) {
  if (text.empty())
    return {};
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()),
      nullptr, 0);
  if (length <= 0)
    return {};
  std::wstring result(static_cast<size_t>(length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), result.data(), length) !=
      length)
    return {};
  return result;
}

bool should_polish(const VoiceInputConfig &config, std::string_view text) {
  const auto endpoint = config.polish_endpoint.empty()
                            ? default_polish_endpoint(config.polish_provider)
                            : config.polish_endpoint;
  const auto model = config.polish_model.empty()
                         ? default_polish_model(config.polish_provider)
                         : config.polish_model;
  return (config.polish_enabled || config.polish_text) && !text.empty() &&
         !config.polish_token.empty() && !endpoint.empty() && !model.empty();
}

std::string polish_prompt(const VoiceInputConfig &config) {
  return polish_prompt_for({config.polish_prompt_id, config.polish_prompt,
                            config.polish_prompt_custom_1,
                            config.polish_prompt_custom_2,
                            config.polish_prompt_custom_3});
}

void send_text_via_send_input(std::wstring_view text) {
  for (const wchar_t ch : text) {
    INPUT input[2]{};
    input[0].type = INPUT_KEYBOARD;
    input[0].ki.wScan = static_cast<WORD>(ch);
    input[0].ki.dwFlags = KEYEVENTF_UNICODE;
    input[1] = input[0];
    input[1].ki.dwFlags |= KEYEVENTF_KEYUP;
    (void)SendInput(2, input, sizeof(INPUT));
  }
}

bool copy_text_to_clipboard(std::wstring_view text) {
  if (!OpenClipboard(nullptr))
    return false;
  const auto bytes = (text.size() + 1) * sizeof(wchar_t);
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!memory) {
    CloseClipboard();
    return false;
  }
  auto *destination = GlobalLock(memory);
  if (!destination) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  std::memcpy(destination, text.data(), text.size() * sizeof(wchar_t));
  static_cast<wchar_t *>(destination)[text.size()] = L'\0';
  GlobalUnlock(memory);
  EmptyClipboard();
  if (!SetClipboardData(CF_UNICODETEXT, memory)) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  CloseClipboard();
  return true;
}

void send_text_via_ctrl_v(std::wstring_view text) {
  if (!copy_text_to_clipboard(text)) {
    send_text_via_send_input(text);
    return;
  }
  Sleep(30);
  INPUT input[4]{};
  input[0].type = INPUT_KEYBOARD;
  input[0].ki.wVk = VK_CONTROL;
  input[1].type = INPUT_KEYBOARD;
  input[1].ki.wVk = 'V';
  input[2] = input[1];
  input[2].ki.dwFlags = KEYEVENTF_KEYUP;
  input[3] = input[0];
  input[3].ki.dwFlags = KEYEVENTF_KEYUP;
  (void)SendInput(4, input, sizeof(INPUT));
}

// The epoch gate prevents generation changes during each visible effect. A new session or a later failure takes the overlay over, so the wait ends early and leaves the overlay to it. This sleeps, so it runs on a worker: the overlay's window belongs to the control thread, and a sleeping control thread would paint nothing and then hide it at once.
void show_voice_failure(WaveOverlay &overlay, VoiceSessionEpoch &session,
                        uint64_t expected, std::atomic<uint64_t> &displays,
                        const std::wstring &message) {
  const uint64_t display = displays.fetch_add(1) + 1;
  if (!session.with_current(expected, [&] {
    overlay.set_listening(false);
    overlay.set_input_level(0.0f);
    overlay.set_show_transcript(true);
    overlay.set_compact_status(WaveOverlay::CompactStatus::None);
    overlay.set_actions_visible(false);
    overlay.set_transcript(message);
    overlay.show();
  }))
    return;
  for (DWORD waited = 0; waited < kFailureDisplayMs; waited += kFailurePollMs) {
    Sleep(kFailurePollMs);
    if (session.load() != expected || displays.load() != display)
      return;
  }
  session.with_current(expected, [&] {
    if (displays.load() != display)
      return;
    overlay.set_transcript(L"");
    overlay.hide();
  });
}
static_assert(std::is_invocable_v<decltype(show_voice_failure), WaveOverlay &,
                                  VoiceSessionEpoch &, uint64_t,
                                  std::atomic<uint64_t> &, const std::wstring &>);
static_assert(!std::is_invocable_v<decltype(show_voice_failure), WaveOverlay &,
                                   uint64_t, uint64_t, std::atomic<uint64_t> &,
                                   const std::wstring &>);
// The epoch must arrive as the live object, never a temporary. That used to be
// asserted through is_invocable with an rvalue argument, but MSVC answers true
// there even though the call itself does not compile - a temporary cannot bind
// to a non-const lvalue reference. Assert the signature instead: it is the
// signature that carries the guarantee, and unlike the trait it reads the same
// on every compiler.
template <typename Signature> struct epoch_parameter;
template <typename Result, typename First, typename Second, typename... Rest>
struct epoch_parameter<Result(First, Second, Rest...)> {
  using type = Second;
};
static_assert(
    std::is_same_v<epoch_parameter<decltype(show_voice_failure)>::type,
                   VoiceSessionEpoch &>);
} // namespace

VoiceInputSession::VoiceInputSession(WaveOverlay &overlay,
                                     LeaseProvider lease_provider,
                                     Sender sender,
                                     ConfigProvider config_provider)
    : overlay_(overlay), lease_provider_(std::move(lease_provider)),
      sender_(std::move(sender)), config_provider_(std::move(config_provider)),
      capture_owner_(std::make_unique<metasequoia::voice::AudioCapture>()) {
  capture_ = capture_owner_.get();
}

VoiceInputSession::~VoiceInputSession() {
  cancel();
  if (capture_)
    capture_->stop();
  {
    std::lock_guard lock(tasks_mutex_);
    for (auto &task : tasks_)
      if (task.valid())
        task.wait();
  }
  // After the recognizers: a finishing one may still report a failure. cancel() moved the epoch on, so each display ends within one poll.
  std::lock_guard lock(notices_mutex_);
  for (auto &notice : notices_)
    if (notice.valid())
      notice.wait();
}

bool VoiceInputSession::init_cues(const std::wstring &start_path,
                                  const std::wstring &end_path) {
  return cue_player_.init(start_path, end_path);
}

bool VoiceInputSession::toggle() {
  if (recording() || starting_.load()) {
    stop();
    return true;
  }
  return start();
}

std::shared_ptr<VoiceReviewResult>
VoiceInputSession::start_review(std::string_view language) {
  if (language.empty() ||
      language.size() > FanyImeVoiceController::MaxLanguageBytes)
    return {};
  for (const unsigned char ch : language)
    if (!((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
          (ch >= '0' && ch <= '9') || ch == '-'))
      return {};
  // A panel must not steal a native recording or its in-flight completion.
  if (recording_.load() || starting_.load())
    return {};
  {
    std::lock_guard lock(tasks_mutex_);
    for (auto &task : tasks_)
      if (task.valid() &&
          task.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
        return {};
  }
  auto review = std::make_shared<VoiceReviewResult>();
  if (!start(review, language)) {
    review->fail();
    return {};
  }
  return review;
}

bool VoiceInputSession::stop_review(
    const std::shared_ptr<VoiceReviewResult> &expected) {
  if (!expected || expected != review_)
    return false;
  stop();
  return true;
}

bool VoiceInputSession::cancel_review(
    const std::shared_ptr<VoiceReviewResult> &expected) {
  if (!expected || expected != review_)
    return false;
  cancel();
  return true;
}

bool VoiceInputSession::start(std::shared_ptr<VoiceReviewResult> review,
                              std::string_view language) {
  if (review_ && review_->active())
    return false;
  if (!capture_ || !lease_provider_ || !sender_ || !config_provider_)
    return false;
  VoiceInputConfig config = config_provider_();
  if (review)
    config.language = std::string(language);
  const bool doubao = is_doubao_asr_provider(config.asr_provider);
  // An endpoint whose transport disagrees with the provider is configuration
  // left behind by an earlier choice, so fall back to this provider's own
  // default rather than posting its token to the previous provider's host.
  // Doubao speaks websocket and the others speak HTTPS, so the scheme is a
  // sufficient test, and existing installs with a stale endpoint are repaired
  // here rather than only for users who re-pick the provider in settings.
  const auto endpoint = resolved_asr_endpoint(config.asr_provider, config.endpoint);
  const auto model = config.model.empty()
                         ? default_asr_model(config.asr_provider)
                         : config.model;
  const bool stream_inline = voice_inline_allowed(
      review, config.stream_inline_preedit, doubao, config.commit_mode);
  // Without a focused input context there is nothing to dictate into, and MSIME-Windows says nothing either.
  const auto lease = lease_provider_();
  if (!lease || !lease->epoch || !lease->token)
    return false;
  // A review capture reports through its own result object; only native recordings are told why they did not start.
  const auto refuse = [&](std::string_view message) {
    if (!review)
      report_failure(message, session_.load());
    return false;
  };
  const auto verdict = voice_start_verdict(
      {config.enabled, doubao, config.token, endpoint, model, config.resource_id});
  if (verdict.check == VoiceStartCheck::Disabled)
    return false;
  if (verdict.check == VoiceStartCheck::Rejected)
    return refuse(verdict.message);
  // A device this host cannot open is a microphone that will not start.
  if (!config.capture.supported())
    return refuse(voice_microphone_start_message);
  bool expected = false;
  if (!starting_.compare_exchange_strong(expected, true))
    return false;
  const uint64_t session = session_.fetch_add(1) + 1;
  review_ = review;
  {
    std::lock_guard lock(config_mutex_);
    active_config_ = config;
  }
  cancel_requested_.store(false);
  locked_.store(false);
  capture_full_.store(false);
  {
    std::lock_guard lock(samples_mutex_);
    samples_.clear();
    captured_frames_ = 0;
  }
  lease_ = *lease;
  const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
  if (doubao) {
    auto client = std::make_shared<DoubaoAsrClient>(
        endpoint, config.doubao_auth_mode, config.app_key, config.token,
        config.resource_id, config.enable_itn, config.enable_punc,
        config.enable_ddc, config.boosting_table_id,
        [this, lease = *lease, generation, session, stream_inline,
         review](const std::string &text) {
          if (review)
            return; // panel receives the final bounded result only
          if (session_.load() != session || cancel_requested_.load())
            return;
          session_.with_current(session, [&] {
            const auto converted = wide(text);
            if (stream_inline) {
              (void)sender_(lease, FanyImeWorkerReplyType::UpdateVoiceComposition,
                            converted, generation);
            } else {
              overlay_.set_transcript(converted);
            }
          });
        });
    {
      std::lock_guard lock(doubao_mutex_);
      doubao_ = client;
    }
    if (!client->Start()) {
      std::lock_guard lock(doubao_mutex_);
      if (doubao_ == client)
        doubao_.reset();
      lease_.reset();
      starting_.store(false);
      return refuse(voice_doubao_start_message);
    }
  }
  const bool started = capture_->start([this, review](const float *samples,
                                                      std::size_t frames) {
    if (!samples || (!recording_.load() && !starting_.load()))
      return;
    double sum = 0.0;
    for (std::size_t i = 0; i < frames; ++i)
      sum += static_cast<double>(samples[i]) * samples[i];
    const float rms = frames ? static_cast<float>(std::sqrt(sum / frames)) : 0.0f;
    const float normalized = std::min(1.0f, std::max(0.0f, rms - 0.004f) * 14.0f);
    const float level = std::pow(normalized, 0.55f);
    if (review)
      review->level(level);
    else
      overlay_.set_input_level(level);
    std::shared_ptr<DoubaoAsrClient> client;
    {
      std::lock_guard doubao_lock(doubao_mutex_);
      client = doubao_;
    }
    // Streaming is not bounded by the batch buffer. Upstream never buffers at all on this path, so stopping the feed at a ceiling threw away the second half of exactly the hands-free dictation the space lock exists for. Only the count is kept, for stop() to recognise a tap too short to transcribe.
    if (client)
      client->PushFloatSamples(samples, frames);
    std::lock_guard lock(samples_mutex_);
    if (client) {
      captured_frames_ += frames;
      return;
    }
    // A batch recording keeps what one upload can carry. When that is reached the recording finishes and submits it, as it does on macOS; maintain() calls stop(), which this capture thread must not.
    const auto capture = voice_batch_capture(captured_frames_, frames,
                                             voice_batch_sample_limit);
    samples_.insert(samples_.end(), samples, samples + capture.keep);
    captured_frames_ += capture.keep;
    if (capture.full)
      capture_full_.store(true);
  }, config.capture.device_id);
  if (!started) {
    std::shared_ptr<DoubaoAsrClient> client;
    {
      std::lock_guard lock(doubao_mutex_);
      client = std::move(doubao_);
    }
    if (client)
      client->Cancel();
    lease_.reset();
    starting_.store(false);
    return refuse(voice_microphone_start_message);
  }
  if (cancel_requested_.load()) {
    capture_->stop();
    std::shared_ptr<DoubaoAsrClient> client;
    {
      std::lock_guard lock(doubao_mutex_);
      client = std::move(doubao_);
    }
    if (client)
      client->Cancel();
    lease_.reset();
    starting_.store(false);
    return false;
  }
  recording_.store(true);
  starting_.store(false);
  if (!review) {
    overlay_.set_input_level(0.0f);
    overlay_.set_listening(true);
    overlay_.set_show_transcript(!stream_inline);
    overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
    overlay_.set_actions_visible(false);
    overlay_.set_transcript(L"");
    overlay_.show();
  }
  if (config.mute_system_audio) {
    mute_other_system_audio();
    muted_system_audio_.store(true);
  }
  if (config.sound_enabled && config.start_sound)
    cue_player_.play_start();
  (void)session;
  return true;
}

void VoiceInputSession::stop() {
  if (!recording_.exchange(false))
    return;
  if (capture_)
    capture_->stop();
  // A callback that threw stopped delivering audio part-way, so what was captured is not the recording the person made. MSIME-Windows StopRecording discards it and says so.
  if (capture_ && capture_->callback_failed()) {
    const bool native = !review_;
    cancel_session(true);
    if (native)
      report_failure(voice_capture_interrupted_message, session_.load());
    return;
  }
  locked_.store(false);
  const auto review = review_;
  if (review)
    review->recognizing();
  overlay_.set_listening(false);
  overlay_.set_input_level(0.0f);
  VoiceInputConfig config;
  {
    std::lock_guard lock(config_mutex_);
    config = active_config_ ? *active_config_ : config_provider_();
  }
  if (muted_system_audio_.exchange(false))
    restore_other_system_audio();
  if (config.sound_enabled && config.end_sound)
    cue_player_.play_end();
  const auto lease = lease_;
  // Keep the target on the control thread so cancel during recognition can
  // retire its inline composition without relying on a stale worker callback.
  std::shared_ptr<DoubaoAsrClient> doubao;
  {
    std::lock_guard lock(doubao_mutex_);
    doubao = doubao_;
  }
  const auto cancel_inline = [&] {
    if (!voice_inline_allowed(review, config.stream_inline_preedit, !!doubao,
                              config.commit_mode) ||
        !lease)
      return;
    const auto generation = static_cast<wchar_t>((session_.load() % 0xfffeu) + 1u);
    const auto encoded = voice_composition_bytes(
        FanyImeWorkerReplyType::CancelVoiceComposition, L"", generation);
    if (encoded)
      (void)sender_(*lease, FanyImeWorkerReplyType::CancelVoiceComposition,
                    L"", generation);
  };
  if (!lease) {
    if (review)
      review->fail();
    if (doubao)
      doubao->Cancel();
    cancel_inline();
    clear_overlay();
    return;
  }
  std::vector<float> samples;
  std::size_t captured_frames = 0;
  {
    std::lock_guard lock(samples_mutex_);
    samples.swap(samples_);
    captured_frames = captured_frames_;
  }
  if (captured_frames < kSampleRate / 4) {
    if (review)
      review->fail();
    if (doubao)
      doubao->Cancel();
    cancel_inline();
    clear_overlay();
    return;
  }
  const uint64_t session = session_.load();
  const bool stream_inline = voice_inline_allowed(
      review, config.stream_inline_preedit, !!doubao, config.commit_mode);
  if (!review) {
    overlay_.set_compact_status(WaveOverlay::CompactStatus::Recognizing);
    overlay_.set_actions_visible(true);
    overlay_.set_show_transcript(!stream_inline);
    overlay_.show();
  }
  std::lock_guard lock(tasks_mutex_);
  tasks_.erase(std::remove_if(tasks_.begin(), tasks_.end(),
                              [](auto &task) {
                                return task.wait_for(std::chrono::seconds(0)) ==
                                       std::future_status::ready;
                              }),
                tasks_.end());
  auto cancelled = std::make_shared<std::atomic_bool>(false);
  {
    std::lock_guard request_lock(request_mutex_);
    request_cancellations_.push_back(cancelled);
  }
  tasks_.emplace_back(std::async(
      std::launch::async,
      [this, samples = std::move(samples), lease = *lease, config, session,
       doubao, review, cancelled = std::move(cancelled)]() mutable {
        finish(std::move(samples), lease, config, session, std::move(doubao),
               std::move(cancelled), review);
      }));
}

void VoiceInputSession::finish(std::vector<float> samples, FocusLease lease,
                               VoiceInputConfig config, uint64_t session,
                               std::shared_ptr<DoubaoAsrClient> doubao,
                               std::shared_ptr<std::atomic_bool> cancelled,
                               std::shared_ptr<VoiceReviewResult> review) {
  const auto clear_current_overlay = [&] {
    if (review)
      review->fail(); // no-op after completion/cancellation
    session_.with_current(session, [&] { clear_overlay(); });
  };
  const auto release_doubao = [&] {
    if (!doubao)
      return;
    std::lock_guard lock(doubao_mutex_);
    if (doubao_ == doubao)
      doubao_.reset();
  };
  const bool stream_inline = voice_inline_allowed(
      review, config.stream_inline_preedit, !!doubao, config.commit_mode);
  const auto cancel_inline = [&] {
    if (!stream_inline)
      return;
    const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
    const auto encoded = voice_composition_bytes(
        FanyImeWorkerReplyType::CancelVoiceComposition, L"", generation);
    if (encoded)
      session_.with_current(session, [&] {
        (void)sender_(lease, FanyImeWorkerReplyType::CancelVoiceComposition, L"",
                      generation);
      });
  };
  if (session_.load() != session || cancel_requested_.load()) {
    clear_current_overlay();
    release_doubao();
    return;
  }
  std::string text;
  try {
    if (doubao) {
      text = doubao->Finish();
      const auto error = doubao->LastError();
      if (text.empty() && !error.empty()) {
        cancel_inline();
        clear_current_overlay();
        release_doubao();
        if (!review && !cancel_requested_.load())
          report_failure(error, session);
        return;
      }
    } else {
      const auto endpoint = resolved_asr_endpoint(config.asr_provider, config.endpoint);
      const auto model = config.model.empty()
                             ? default_asr_model(config.asr_provider)
                             : config.model;
      text = recognize_cloud_asr(samples, config.asr_provider, endpoint, model,
                                 config.token, config.language, cancelled);
    }
  } catch (const std::exception &error) {
    cancel_inline();
    clear_current_overlay();
    release_doubao();
    if (!review && !cancel_requested_.load())
      report_failure(voice_recognition_failure(error), session);
    return;
  }
  if (session_.load() != session || cancel_requested_.load() || text.empty()) {
    cancel_inline();
    clear_current_overlay();
    release_doubao();
    return;
  }
  if (!review)
    session_.with_current(session,
                          [&] { overlay_.set_transcript(wide(text)); });
  std::string final_text = text;
  if (should_polish(config, text)) {
    if (review)
      review->processing();
    else
      session_.with_current(session, [&] {
        overlay_.set_compact_status(WaveOverlay::CompactStatus::Processing);
        overlay_.set_actions_visible(true);
        overlay_.show();
      });
    const auto endpoint = config.polish_endpoint.empty()
                              ? default_polish_endpoint(config.polish_provider)
                              : config.polish_endpoint;
    const auto model = config.polish_model.empty()
                           ? default_polish_model(config.polish_provider)
                           : config.polish_model;
    // Polishing is best-effort, as it is upstream: a transport error, a non-2xx
    // status or a missing body must not cost the user a transcript the ASR has
    // already produced. The exception used to escape into the std::async future
    // - which is only wait()ed, never get() - so the text vanished silently.
    try {
      auto polished =
          polish_cloud_text(text, config.polish_provider, endpoint, model,
                            config.polish_token, polish_prompt(config),
                            cancelled);
      if (!polished.empty())
        final_text = std::move(polished);
    } catch (const std::exception &) {
      final_text = text;
    }
  }
  if (session_.load() != session || cancel_requested_.load() ||
      final_text.empty()) {
    cancel_inline();
    clear_current_overlay();
    release_doubao();
    return;
  }
  session_.with_current(session, [&] {
    deliver_voice_result(review, final_text, [&] {
      overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
      overlay_.set_transcript(wide(final_text));
      const auto converted = wide(final_text);
      const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
      if (config.commit_mode == "sendinput") {
        send_text_via_send_input(converted);
        clear_overlay();
      } else if (config.commit_mode == "ctrl_v") {
        send_text_via_ctrl_v(converted);
        clear_overlay();
      } else {
        const auto encoded = voice_composition_bytes(
            FanyImeWorkerReplyType::CommitVoiceComposition, converted,
            generation);
        if (encoded &&
            sender_(lease, FanyImeWorkerReplyType::CommitVoiceComposition,
                    converted, generation) == VoiceCompositionResult::Sent) {
          clear_overlay();
        } else {
          // The TSF route was refused - focus moved to a window with no text
          // service, or the transaction lock was busy. Upstream falls back to
          // SendInput rather than dropping the text, which is the whole
          // recording.
          if (stream_inline)
            (void)sender_(lease, FanyImeWorkerReplyType::CancelVoiceComposition,
                          L"", generation);
          send_text_via_send_input(converted);
          clear_overlay();
        }
      }
    });
  });
  release_doubao();
  {
    std::lock_guard lock(config_mutex_);
    if (active_config_ && session_.load() == session)
      active_config_.reset();
  }
}

void VoiceInputSession::cancel() { cancel_session(false); }

void VoiceInputSession::cancel_session(bool failed) {
  const auto review = review_;
  if (review) {
    if (failed)
      review->fail();
    else
      review->cancel();
  }
  const bool was_recording = recording_.exchange(false);
  cancel_requested_.store(true);
  const auto session = session_.fetch_add(1);
  locked_.store(false);
  VoiceInputConfig config;
  {
    std::lock_guard lock(config_mutex_);
    config = active_config_ ? *active_config_ : config_provider_();
  }
  {
    std::lock_guard request_lock(request_mutex_);
    for (const auto &request : request_cancellations_)
      request->store(true);
  }
  const auto lease = lease_;
  lease_.reset();
  if ((was_recording || starting_.load()) && capture_)
    capture_->stop();
  std::shared_ptr<DoubaoAsrClient> doubao;
  {
    std::lock_guard lock(doubao_mutex_);
    doubao = doubao_;
  }
  if (doubao)
    doubao->Cancel();
  if (muted_system_audio_.exchange(false))
    restore_other_system_audio();
  if (was_recording && config.sound_enabled && config.end_sound)
    cue_player_.play_end();
  if (lease && !review) {
    const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
    const auto encoded = voice_composition_bytes(
        FanyImeWorkerReplyType::CancelVoiceComposition, L"", generation);
    if (encoded)
      (void)sender_(*lease, FanyImeWorkerReplyType::CancelVoiceComposition,
                    L"", generation);
  }
  clear_overlay();
  {
    std::lock_guard lock(config_mutex_);
    active_config_.reset();
  }
}

void VoiceInputSession::lock() {
  if (!recording_.load())
    return;
  locked_.store(true);
  if (voice_lock_shows_actions(true, !!review_)) {
    overlay_.set_actions_visible(true);
    overlay_.show();
  }
}

void VoiceInputSession::maintain() {
  if (!recording_.load())
    return;
  if (capture_ && capture_->callback_failed()) {
    // Detected while still recording rather than when the key comes up: a locked recording could otherwise sit on a dead microphone indefinitely.
    const bool native = !review_;
    cancel_session(true);
    if (native)
      report_failure(voice_capture_interrupted_message, session_.load());
    return;
  }
  if (capture_full_.load())
    stop();
}

void VoiceInputSession::report_failure(std::string_view message,
                                       uint64_t session) {
  auto text = wide(message);
  if (text.empty())
    return;
  std::lock_guard lock(notices_mutex_);
  notices_.erase(std::remove_if(notices_.begin(), notices_.end(),
                                [](auto &notice) {
                                  return notice.wait_for(std::chrono::seconds(0)) ==
                                         std::future_status::ready;
                                }),
                 notices_.end());
  notices_.emplace_back(std::async(
      std::launch::async, [this, text = std::move(text), session] {
        show_voice_failure(overlay_, session_, session, failure_displays_, text);
      }));
}

void VoiceInputSession::clear_overlay() {
  overlay_.set_listening(false);
  overlay_.set_input_level(0.0f);
  overlay_.set_show_transcript(true);
  overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
  overlay_.set_actions_visible(false);
  overlay_.set_transcript(L"");
  overlay_.hide();
}
} // namespace msime::windows

#include "VoiceInputSession.h"
#include "PolishPrompt.h"

#include "ReplyCodec.h"
#include "SystemAudioMuter.h"
#include "VoiceProviders.h"
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
constexpr std::size_t kMaximumSamples = kSampleRate * 60;

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

// The epoch gate prevents generation changes during each visible effect.
void show_voice_failure(WaveOverlay &overlay, VoiceSessionEpoch &session,
                        uint64_t expected, const wchar_t *message) {
  if (!session.with_current(expected, [&] {
    overlay.set_show_transcript(true);
    overlay.set_compact_status(WaveOverlay::CompactStatus::None);
    overlay.set_actions_visible(false);
    overlay.set_transcript(message);
    overlay.show();
  }))
    return;
  Sleep(1200);
  session.with_current(expected, [&] { overlay.hide(); });
}
static_assert(std::is_invocable_v<decltype(show_voice_failure), WaveOverlay &,
                                  VoiceSessionEpoch &, uint64_t,
                                  const wchar_t *>);
static_assert(!std::is_invocable_v<decltype(show_voice_failure), WaveOverlay &,
                                   uint64_t, uint64_t, const wchar_t *>);
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
  std::lock_guard lock(tasks_mutex_);
  for (auto &task : tasks_)
    if (task.valid())
      task.wait();
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

bool VoiceInputSession::start() {
  if (!capture_ || !lease_provider_ || !sender_ || !config_provider_)
    return false;
  const VoiceInputConfig config = config_provider_();
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
  const bool stream_inline = config.stream_inline_preedit && doubao &&
                             config.commit_mode == "tsf";
  if (!config.enabled || config.token.empty() || endpoint.empty() ||
      (!doubao && model.empty()) || (doubao && config.resource_id.empty()))
    return false;
  const auto lease = lease_provider_();
  if (!lease || !lease->epoch || !lease->token)
    return false;
  bool expected = false;
  if (!starting_.compare_exchange_strong(expected, true))
    return false;
  const uint64_t session = session_.fetch_add(1) + 1;
  {
    std::lock_guard lock(config_mutex_);
    active_config_ = config;
  }
  cancel_requested_.store(false);
  locked_.store(false);
  capture_overflow_.store(false);
  {
    std::lock_guard lock(samples_mutex_);
    samples_.clear();
    captured_frames_ = 0;
  }
  lease_ = *lease;
  const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
  if (doubao) {
    auto client = std::make_shared<DoubaoAsrClient>(
        endpoint, config.app_key, config.token, config.resource_id,
        config.enable_itn, config.enable_punc, config.enable_ddc,
        config.boosting_table_id,
        [this, lease = *lease, generation, session,
         stream_inline](const std::string &text) {
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
      return false;
    }
  }
  const bool started = capture_->start([this](const float *samples,
                                               std::size_t frames) {
    if (!samples || (!recording_.load() && !starting_.load()))
      return;
    double sum = 0.0;
    for (std::size_t i = 0; i < frames; ++i)
      sum += static_cast<double>(samples[i]) * samples[i];
    const float rms = frames ? static_cast<float>(std::sqrt(sum / frames)) : 0.0f;
    const float normalized = std::min(1.0f, std::max(0.0f, rms - 0.004f) * 14.0f);
    overlay_.set_input_level(std::pow(normalized, 0.55f));
    std::shared_ptr<DoubaoAsrClient> client;
    {
      std::lock_guard doubao_lock(doubao_mutex_);
      client = doubao_;
    }
    // Streaming is not bounded by the batch buffer. Upstream never buffers at
    // all on this path, so stopping the feed at 60 s threw away the second
    // half of exactly the hands-free dictation the space lock exists for.
    if (client)
      client->PushFloatSamples(samples, frames);
    std::lock_guard lock(samples_mutex_);
    if (captured_frames_ >= kMaximumSamples ||
        frames > kMaximumSamples - captured_frames_) {
      // The batch upload still has a ceiling; record that it was reached so
      // stop() can say so instead of committing nothing without explanation.
      capture_overflow_.store(true);
      return;
    }
    samples_.insert(samples_.end(), samples, samples + frames);
    captured_frames_ += frames;
  });
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
    return false;
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
  overlay_.set_input_level(0.0f);
  overlay_.set_listening(true);
  overlay_.set_show_transcript(!stream_inline);
  overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
  overlay_.set_actions_visible(false);
  overlay_.set_transcript(L"");
  overlay_.show();
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
  locked_.store(false);
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
    if (!config.stream_inline_preedit || !doubao || !lease)
      return;
    const auto generation = static_cast<wchar_t>((session_.load() % 0xfffeu) + 1u);
    const auto encoded = voice_composition_bytes(
        FanyImeWorkerReplyType::CancelVoiceComposition, L"", generation);
    if (encoded)
      (void)sender_(*lease, FanyImeWorkerReplyType::CancelVoiceComposition,
                    L"", generation);
  };
  // Overflow only matters when the batch buffer is what gets uploaded; the
  // streaming client has its own transcript and was fed throughout.
  const bool overflowed = capture_overflow_.load() && !doubao;
  if (!lease || overflowed) {
    if (doubao)
      doubao->Cancel();
    cancel_inline();
    if (overflowed && lease)
      show_voice_failure(overlay_, session_, session_.load(),
                         L"录音超过 60 秒上限");
    clear_overlay();
    return;
  }
  std::vector<float> samples;
  {
    std::lock_guard lock(samples_mutex_);
    samples.swap(samples_);
  }
  if (samples.size() < kSampleRate / 4) {
    if (doubao)
      doubao->Cancel();
    cancel_inline();
    clear_overlay();
    return;
  }
  const uint64_t session = session_.load();
  const bool stream_inline = config.stream_inline_preedit && doubao &&
                             config.commit_mode == "tsf";
  overlay_.set_compact_status(WaveOverlay::CompactStatus::Recognizing);
  overlay_.set_actions_visible(true);
  overlay_.set_show_transcript(!stream_inline);
  overlay_.show();
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
      std::launch::async, [this, samples = std::move(samples), lease = *lease,
                           config, session, doubao,
                           cancelled = std::move(cancelled)]() mutable {
        finish(std::move(samples), lease, config, session, std::move(doubao),
               std::move(cancelled));
      }));
}

void VoiceInputSession::finish(std::vector<float> samples, FocusLease lease,
                               VoiceInputConfig config, uint64_t session,
                               std::shared_ptr<DoubaoAsrClient> doubao,
                               std::shared_ptr<std::atomic_bool> cancelled) {
  const auto clear_current_overlay = [&] {
    session_.with_current(session, [&] { clear_overlay(); });
  };
  const auto release_doubao = [&] {
    if (!doubao)
      return;
    std::lock_guard lock(doubao_mutex_);
    if (doubao_ == doubao)
      doubao_.reset();
  };
  const bool stream_inline = config.stream_inline_preedit && doubao &&
                             config.commit_mode == "tsf";
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
      if (text.empty() && !doubao->LastError().empty()) {
        cancel_inline();
        clear_current_overlay();
        release_doubao();
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
  } catch (const std::exception &) {
    cancel_inline();
    if (!cancel_requested_.load())
      show_voice_failure(overlay_, session_, session, L"语音识别失败");
    clear_current_overlay();
    release_doubao();
    return;
  }
  if (session_.load() != session || cancel_requested_.load() || text.empty()) {
    cancel_inline();
    clear_current_overlay();
    release_doubao();
    return;
  }
  session_.with_current(session, [&] { overlay_.set_transcript(wide(text)); });
  std::string final_text = text;
  if (should_polish(config, text)) {
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
  release_doubao();
  {
    std::lock_guard lock(config_mutex_);
    if (active_config_ && session_.load() == session)
      active_config_.reset();
  }
}

void VoiceInputSession::cancel() {
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
  if (lease) {
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
  if (recording_.load())
    locked_.store(true);
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

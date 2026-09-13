#include "VoiceInputSession.h"

#include "ReplyCodec.h"
#include <msime/voice/audio_capture.h>
#include <msime/voice/cloud_stt_worker.h>
#include <msime/voice/provider_protocol.h>

#include <algorithm>
#include <chrono>
#include <cmath>

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
  if (!config.enabled || config.token.empty() || config.endpoint.empty() ||
      config.model.empty())
    return false;
  const auto lease = lease_provider_();
  if (!lease || !lease->epoch || !lease->token)
    return false;
  bool expected = false;
  if (!starting_.compare_exchange_strong(expected, true))
    return false;
  cancel_requested_.store(false);
  capture_overflow_.store(false);
  {
    std::lock_guard lock(samples_mutex_);
    samples_.clear();
    captured_frames_ = 0;
  }
  const uint64_t session = session_.fetch_add(1) + 1;
  lease_ = *lease;
  const bool started = capture_->start([this](const float *samples,
                                               std::size_t frames) {
    if (!samples || !recording_.load() && !starting_.load())
      return;
    double sum = 0.0;
    for (std::size_t i = 0; i < frames; ++i)
      sum += static_cast<double>(samples[i]) * samples[i];
    const float rms = frames ? static_cast<float>(std::sqrt(sum / frames)) : 0.0f;
    const float normalized = std::min(1.0f, std::max(0.0f, rms - 0.004f) * 14.0f);
    overlay_.set_input_level(std::pow(normalized, 0.55f));
    std::lock_guard lock(samples_mutex_);
    if (captured_frames_ >= kMaximumSamples ||
        frames > kMaximumSamples - captured_frames_) {
      capture_overflow_.store(true);
      return;
    }
    samples_.insert(samples_.end(), samples, samples + frames);
    captured_frames_ += frames;
  });
  if (!started) {
    starting_.store(false);
    return false;
  }
  if (cancel_requested_.load()) {
    capture_->stop();
    starting_.store(false);
    return false;
  }
  recording_.store(true);
  starting_.store(false);
  overlay_.set_input_level(0.0f);
  overlay_.set_listening(true);
  overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
  overlay_.set_actions_visible(false);
  overlay_.set_transcript(L"");
  overlay_.show();
  (void)config.start_sound;
  (void)session;
  return true;
}

void VoiceInputSession::stop() {
  if (!recording_.exchange(false))
    return;
  if (capture_)
    capture_->stop();
  overlay_.set_listening(false);
  overlay_.set_input_level(0.0f);
  const auto config = config_provider_();
  const auto lease = lease_;
  lease_.reset();
  if (!lease || capture_overflow_.load()) {
    clear_overlay();
    return;
  }
  std::vector<float> samples;
  {
    std::lock_guard lock(samples_mutex_);
    samples.swap(samples_);
  }
  if (samples.size() < kSampleRate / 4) {
    clear_overlay();
    return;
  }
  const uint64_t session = session_.load();
  overlay_.set_compact_status(WaveOverlay::CompactStatus::Recognizing);
  overlay_.set_actions_visible(false);
  overlay_.show();
  std::lock_guard lock(tasks_mutex_);
  tasks_.erase(std::remove_if(tasks_.begin(), tasks_.end(),
                              [](auto &task) {
                                return task.wait_for(std::chrono::seconds(0)) ==
                                       std::future_status::ready;
                              }),
                tasks_.end());
  tasks_.emplace_back(std::async(
      std::launch::async, [this, samples = std::move(samples), lease = *lease,
                           config, session]() mutable {
        finish(std::move(samples), lease, config, session);
      }));
}

void VoiceInputSession::finish(std::vector<float> samples, FocusLease lease,
                               VoiceInputConfig config, uint64_t session) {
  auto cancelled = std::make_shared<std::atomic_bool>(false);
  if (session_.load() != session || cancel_requested_.load()) {
    clear_overlay();
    return;
  }
  metasequoia::voice::CloudSttWorker recognizer(
      metasequoia::voice::RequestOptions{config.endpoint, config.model,
                                         config.token, 10000, cancelled});
  std::string text;
  try {
    text = recognizer.recognize(samples);
  } catch (const std::exception &) {
    clear_overlay();
    return;
  }
  if (session_.load() != session || cancel_requested_.load() || text.empty()) {
    clear_overlay();
    return;
  }
  overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
  overlay_.set_transcript(wide(text));
  const auto converted = wide(text);
  const auto generation = static_cast<wchar_t>((session % 0xfffeu) + 1u);
  const auto encoded = voice_composition_bytes(
      FanyImeWorkerReplyType::CommitVoiceComposition, converted, generation);
  if (encoded && sender_(lease, FanyImeWorkerReplyType::CommitVoiceComposition,
                        converted, generation) ==
                    VoiceCompositionResult::Sent)
    clear_overlay();
  else
    clear_overlay();
}

void VoiceInputSession::cancel() {
  cancel_requested_.store(true);
  session_.fetch_add(1);
  lease_.reset();
  if (recording_.exchange(false) && capture_)
    capture_->stop();
  clear_overlay();
}

void VoiceInputSession::clear_overlay() {
  overlay_.set_listening(false);
  overlay_.set_input_level(0.0f);
  overlay_.set_compact_status(WaveOverlay::CompactStatus::None);
  overlay_.set_actions_visible(false);
  overlay_.set_transcript(L"");
  overlay_.hide();
}
} // namespace msime::windows

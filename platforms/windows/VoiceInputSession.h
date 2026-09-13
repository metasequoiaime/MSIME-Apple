#pragma once

#include "FocusGate.h"
#include "SessionController.h"
#include "WaveOverlay.h"
#include "DoubaoAsrClient.h"
#include "CuePlayer.h"
#include <atomic>
#include <functional>
#include <future>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace metasequoia::voice {
class AudioCapture;
}

namespace msime::windows {
struct VoiceInputConfig {
  bool enabled = true;
  bool start_sound = true;
  bool end_sound = true;
  bool sound_enabled = true;
  bool mute_system_audio = false;
  bool hotkey_ralt = true;
  bool hotkey_ctrl_f9 = true;
  bool hotkey_ctrl_win = false;
  bool hotkey_rctrl_ralt = false;
  bool hotkey_hold_space_lock = true;
  bool stream_inline_preedit = true;
  std::string asr_provider = "doubao";
  std::string endpoint;
  std::string model;
  std::string token;
  std::string app_key;
  std::string resource_id;
  bool enable_itn = true;
  bool enable_punc = true;
  bool enable_ddc = false;
  std::string boosting_table_id;
  std::string language = "zh-cn";
  bool polish_enabled = false;
  bool polish_text = false;
  std::string polish_provider;
  std::string polish_token;
  std::string polish_endpoint;
  std::string polish_model;
  std::string polish_prompt_id = "cleanup";
  std::string polish_prompt;
  std::string polish_prompt_custom_1;
  std::string polish_prompt_custom_2;
  std::string polish_prompt_custom_3;
};

// Owns microphone capture and the asynchronous batch recognizer. All UI
// state is represented by WaveOverlay; no capture callback calls stop or
// touches the Windows window procedure directly.
class VoiceInputSession final {
public:
  using LeaseProvider = std::function<std::optional<FocusLease>()>;
  using Sender = std::function<VoiceCompositionResult(
      const FocusLease &, uint32_t, std::wstring_view, wchar_t)>;
  using ConfigProvider = std::function<VoiceInputConfig()>;

  VoiceInputSession(WaveOverlay &overlay, LeaseProvider lease_provider,
                    Sender sender, ConfigProvider config_provider);
  ~VoiceInputSession();
  VoiceInputSession(const VoiceInputSession &) = delete;
  VoiceInputSession &operator=(const VoiceInputSession &) = delete;

  bool toggle();
  void stop();
  void cancel();
  void lock();
  bool init_cues(const std::wstring &start_path, const std::wstring &end_path);
  bool recording() const { return recording_.load(); }
  bool locked() const { return locked_.load(); }

private:
  bool start();
  void finish(std::vector<float> samples, FocusLease lease,
              VoiceInputConfig config, uint64_t session,
              std::shared_ptr<DoubaoAsrClient> doubao);
  void clear_overlay();

  WaveOverlay &overlay_;
  LeaseProvider lease_provider_;
  Sender sender_;
  ConfigProvider config_provider_;
  metasequoia::voice::AudioCapture *capture_ = nullptr;
  std::unique_ptr<metasequoia::voice::AudioCapture> capture_owner_;
  CuePlayer cue_player_;
  std::atomic<bool> recording_{false};
  std::atomic<bool> starting_{false};
  std::atomic<bool> locked_{false};
  std::atomic<bool> cancel_requested_{false};
  std::atomic<uint64_t> session_{0};
  std::mutex samples_mutex_;
  std::vector<float> samples_;
  std::size_t captured_frames_ = 0;
  std::atomic<bool> capture_overflow_{false};
  std::optional<FocusLease> lease_;
  std::mutex doubao_mutex_;
  std::shared_ptr<DoubaoAsrClient> doubao_;
  std::atomic<bool> muted_system_audio_{false};
  std::mutex tasks_mutex_;
  std::vector<std::future<void>> tasks_;
};
} // namespace msime::windows

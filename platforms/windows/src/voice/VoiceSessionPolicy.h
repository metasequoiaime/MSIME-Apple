#pragma once
// Decisions VoiceInputSession makes that need no Win32: how much of a capture callback a batch recording keeps, and which sentence the person dictating is shown when a recording cannot start or does not produce text. The wording is MSIME-Windows voice_input_service.cpp's, which shows each of these in a message box; this host shows them on the voice overlay instead.

#include "VoiceProviders.h"

#include <cstddef>
#include <exception>
#include <string>
#include <string_view>

namespace msime::windows {
// What a batch recording keeps of one capture callback. `keep` frames are appended; `full` means the buffer has reached `limit` and the recording should finish now and submit what it holds, the way the macOS host does, rather than keep listening to audio it would drop.
struct VoiceBatchCapture {
  std::size_t keep = 0;
  bool full = false;
};

constexpr VoiceBatchCapture voice_batch_capture(std::size_t captured,
                                                std::size_t frames,
                                                std::size_t limit) {
  if (captured >= limit)
    return {0, true};
  const std::size_t room = limit - captured;
  if (frames >= room)
    return {room, true};
  return {frames, false};
}

// The batch buffer is bounded by what one upload can carry, not by a fixed minute count: MSIME-Windows only rejects a recording at its 20 MiB upload check.
inline constexpr std::size_t voice_batch_sample_limit = batch_capture_sample_limit;

inline constexpr std::string_view voice_missing_token_message =
    "请先在设置的“语音输入”分区填写当前 ASR 提供商的 API Token。";
inline constexpr std::string_view voice_missing_endpoint_message =
    "ASR Token 或接口地址为空。";
inline constexpr std::string_view voice_missing_model_message = "ASR 模型名为空。";
// MSIME-Windows ends this sentence with "请检查 config.toml。"; here the same fields are edited in the settings page.
inline constexpr std::string_view voice_doubao_start_message =
    "无法启动豆包流式语音识别。请检查“语音输入”设置中的接口地址、凭据和资源 ID。";
inline constexpr std::string_view voice_microphone_start_message = "无法启动麦克风。";
inline constexpr std::string_view voice_capture_interrupted_message = "录音中断，请重试。";
inline constexpr std::string_view voice_recognition_failed_message = "语音识别失败";

// The configuration a recording needs before anything is opened.
struct VoiceStartConfig {
  bool enabled = true;
  bool doubao = false;
  std::string_view token;
  std::string_view endpoint;
  std::string_view model;
  std::string_view resource_id;
};

enum class VoiceStartCheck { Ready, Disabled, Rejected };

struct VoiceStartVerdict {
  VoiceStartCheck check = VoiceStartCheck::Ready;
  // Empty unless `check` is Rejected. A disabled voice input stays silent, as it does in MSIME-Windows.
  std::string_view message;
};

constexpr VoiceStartVerdict voice_start_verdict(const VoiceStartConfig &config) {
  if (!config.enabled)
    return {VoiceStartCheck::Disabled, {}};
  if (config.token.empty())
    return {VoiceStartCheck::Rejected, voice_missing_token_message};
  // MSIME-Windows hands an incomplete Doubao configuration to the streaming client, whose Start() refuses it; a batch provider's gaps surface in Recognize().
  if (config.doubao && (config.endpoint.empty() || config.resource_id.empty()))
    return {VoiceStartCheck::Rejected, voice_doubao_start_message};
  if (config.endpoint.empty())
    return {VoiceStartCheck::Rejected, voice_missing_endpoint_message};
  if (!config.doubao && config.model.empty())
    return {VoiceStartCheck::Rejected, voice_missing_model_message};
  return {};
}

// The sentence for a failed batch recognition: the provider's own message or HTTP status when the shared client supplied one, the generic line otherwise.
inline std::string voice_recognition_failure(const std::exception &error) {
  if (const auto *cloud = dynamic_cast<const CloudAsrError *>(&error))
    if (!cloud->user_message().empty())
      return cloud->user_message();
  return std::string(voice_recognition_failed_message);
}

// The ✓ and ✗ buttons appear once a native recording is locked, as in MSIME-Windows ControlLoop: the key that started it is up, so the overlay is the only place left to end it besides the shortcut and Escape. A review capture has no overlay.
constexpr bool voice_lock_shows_actions(bool recording, bool review) {
  return recording && !review;
}
} // namespace msime::windows

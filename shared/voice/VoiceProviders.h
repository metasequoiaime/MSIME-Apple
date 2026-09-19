#pragma once
// Platform-independent provider adaptation. Preserve historical Windows ABI;
// new hosts use the platform-neutral aliases below.

#include <string>
#include <string_view>
#include <atomic>
#include <memory>
#include <vector>

namespace msime::windows {
std::string transcription_language(std::string_view provider, std::string_view language);
std::string normalize_voice_provider(std::string_view provider);
std::string default_asr_endpoint(std::string_view provider);
std::string default_asr_model(std::string_view provider);
std::string default_polish_endpoint(std::string_view provider);
std::string default_polish_model(std::string_view provider);
// True when the configured provider is Doubao. Deliberately ignores the
// endpoint: see the definition for why trusting it leaked tokens.
bool is_doubao_asr_provider(std::string_view provider);
// ws:// or wss://. Used to spot an endpoint left over from another provider.
bool voice_endpoint_is_websocket(std::string_view endpoint);
std::string resolved_asr_endpoint(std::string_view provider,
                                  std::string_view configured_endpoint);
std::string recognize_cloud_asr(
    const std::vector<float> &samples, std::string_view provider,
    std::string_view endpoint, std::string_view model, std::string_view token,
    std::string_view language,
    const std::shared_ptr<std::atomic_bool> &cancelled);
std::string polish_cloud_text(
    std::string_view text, std::string_view provider, std::string_view endpoint,
    std::string_view model, std::string_view token, std::string_view prompt,
    const std::shared_ptr<std::atomic_bool> &cancelled);
// Whether this build carries the on-device Whisper provider. Hosts offer the "local" provider only when it answers true; without it the recognizer below always throws, and a host that advertised the option anyway would fall back to the platform recognizer without saying so.
bool local_asr_available();
// Transcribe on this machine with the model file at `model_path`. Nothing leaves the process. `language` is the host's language tag; "auto" asks Whisper to detect. Throws VoiceError when the build has no Whisper, the model cannot be loaded, or the request was cancelled.
std::string recognize_local_asr(
    const std::vector<float> &samples, std::string_view model_path,
    std::string_view language,
    const std::shared_ptr<std::atomic_bool> &cancelled);
}
namespace msime::voice {
using windows::transcription_language;
using windows::normalize_voice_provider;
using windows::default_asr_endpoint;
using windows::default_asr_model;
using windows::default_polish_endpoint;
using windows::default_polish_model;
using windows::is_doubao_asr_provider;
using windows::voice_endpoint_is_websocket;
using windows::resolved_asr_endpoint;
using windows::recognize_cloud_asr;
using windows::polish_cloud_text;
using windows::local_asr_available;
using windows::recognize_local_asr;
}

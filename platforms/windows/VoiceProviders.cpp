#include "VoiceProviders.h"

namespace msime::windows {
namespace {
std::string lower(std::string_view value) {
  std::string result(value);
  for (char &ch : result)
    if (ch >= 'A' && ch <= 'Z')
      ch = static_cast<char>(ch - 'A' + 'a');
  return result;
}
} // namespace

std::string normalize_voice_provider(std::string_view provider) {
  const auto result = lower(provider);
  if (result == "cloud")
    return "siliconflow";
  return result.empty() ? "doubao" : result;
}

std::string default_asr_endpoint(std::string_view provider) {
  const auto id = normalize_voice_provider(provider);
  if (id == "openai")
    return "https://api.openai.com/v1/audio/transcriptions";
  if (id == "groq")
    return "https://api.groq.com/openai/v1/audio/transcriptions";
  if (id == "siliconflow")
    return "https://api.siliconflow.cn/v1/audio/transcriptions";
  return "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async";
}

std::string default_asr_model(std::string_view provider) {
  const auto id = normalize_voice_provider(provider);
  if (id == "openai")
    return "whisper-1";
  if (id == "groq")
    return "whisper-large-v3-turbo";
  if (id == "siliconflow")
    return "FunAudioLLM/SenseVoiceSmall";
  return {};
}

bool is_doubao_asr_provider(std::string_view provider,
                            std::string_view endpoint) {
  return normalize_voice_provider(provider) == "doubao" ||
         endpoint.rfind("wss://", 0) == 0;
}
} // namespace msime::windows

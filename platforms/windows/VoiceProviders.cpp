#include "VoiceProviders.h"

#include <msime/voice/provider_protocol.h>
#include <msime/voice/stt_service.h>
#include <msime/voice/wav_writer.h>
#include <curl/curl.h>

#include <algorithm>
#include <chrono>
#include <limits>
#include <mutex>
#include <thread>
#include <utility>

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

namespace {
struct Response {
  std::string body;
};

size_t write_response(char *data, size_t size, size_t count, void *context) {
  if (size && count > (std::numeric_limits<size_t>::max)() / size)
    return 0;
  const auto length = size * count;
  auto &response = *static_cast<Response *>(context);
  if (length > 1024 * 1024 - response.body.size())
    return 0;
  response.body.append(data, length);
  return length;
}

int progress(void *context, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
  const auto *cancelled = static_cast<const std::atomic_bool *>(context);
  return cancelled && cancelled->load() ? 1 : 0;
}

void initialize_curl() {
  static std::once_flag once;
  static CURLcode result = CURLE_OK;
  std::call_once(once, [] { result = curl_global_init(CURL_GLOBAL_DEFAULT); });
  if (result != CURLE_OK)
    throw metasequoia::voice::VoiceError("Cannot initialize HTTP runtime");
}
} // namespace

std::string recognize_cloud_asr(
    const std::vector<float> &samples, std::string_view provider,
    std::string_view endpoint, std::string_view model, std::string_view token,
    std::string_view language,
    const std::shared_ptr<std::atomic_bool> &cancelled) {
  if (samples.empty())
    return {};
  const auto id = normalize_voice_provider(provider);
  if (endpoint.empty() || model.empty() || token.empty())
    throw metasequoia::voice::VoiceError("Voice endpoint, model and token are required");
  if (cancelled && cancelled->load())
    throw metasequoia::voice::VoiceError("Voice request cancelled");

  std::vector<float> padded;
  const std::vector<float> *audio = &samples;
  if (id == "siliconflow") {
    constexpr size_t padding = metasequoia::voice::sample_rate / 5;
    padded.reserve(samples.size() + padding * 2);
    padded.insert(padded.end(), padding, 0.0f);
    padded.insert(padded.end(), samples.begin(), samples.end());
    padded.insert(padded.end(), padding, 0.0f);
    if (padded.size() < static_cast<size_t>(metasequoia::voice::sample_rate))
      padded.resize(metasequoia::voice::sample_rate, 0.0f);
    audio = &padded;
  }
  constexpr size_t upload_sample_limit =
      (metasequoia::voice::maximum_encoded_audio_bytes - 44) / 2;
  const auto wav = metasequoia::voice::WavWriter::create_wav(
      *audio, metasequoia::voice::sample_rate, upload_sample_limit);
  const auto request_language = id == "siliconflow"
                                    ? std::string_view{}
                                    : language == "zh-cn" ? std::string_view{"zh"}
                                    : language == "en" ? std::string_view{"en"}
                                                         : language;
  const auto payload = metasequoia::voice::make_transcription_request(
      std::string_view(reinterpret_cast<const char *>(wav.data()), wav.size()),
      model, request_language);
  initialize_curl();
  const std::string endpoint_value(endpoint);

  const int attempts = id == "siliconflow" ? 2 : 1;
  std::string response;
  long status = 0;
  CURLcode result = CURLE_OK;
  char error[CURL_ERROR_SIZE] = {};
  for (int attempt = 0; attempt < attempts; ++attempt) {
    if (attempt)
      std::this_thread::sleep_for(std::chrono::milliseconds(400));
    if (cancelled && cancelled->load())
      throw metasequoia::voice::VoiceError("Voice request cancelled");
    response.clear();
    Response response_data;
    error[0] = '\0';
    std::unique_ptr<CURL, decltype(&curl_easy_cleanup)> curl(
        curl_easy_init(), curl_easy_cleanup);
    if (!curl)
      throw metasequoia::voice::VoiceError("Cannot create HTTP request");
    std::unique_ptr<curl_slist, decltype(&curl_slist_free_all)> headers(
        curl_slist_append(nullptr, ("Authorization: Bearer " +
                                    std::string(token))
                               .c_str()),
        curl_slist_free_all);
    if (!headers)
      throw metasequoia::voice::VoiceError("Cannot create HTTP headers");
    auto *next = curl_slist_append(headers.get(), "Expect:");
    if (!next)
      throw metasequoia::voice::VoiceError("Cannot create HTTP headers");
    headers.release();
    headers.reset(next);
    next = curl_slist_append(headers.get(),
                             ("Content-Type: " + payload.content_type).c_str());
    if (!next)
      throw metasequoia::voice::VoiceError("Cannot create HTTP headers");
    headers.release();
    headers.reset(next);
    curl_easy_setopt(curl.get(), CURLOPT_URL, endpoint_value.c_str());
    curl_easy_setopt(curl.get(), CURLOPT_HTTPHEADER, headers.get());
    curl_easy_setopt(curl.get(), CURLOPT_POST, 1L);
    curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDS, payload.body.data());
    curl_easy_setopt(curl.get(), CURLOPT_POSTFIELDSIZE_LARGE,
                     static_cast<curl_off_t>(payload.body.size()));
    curl_easy_setopt(curl.get(), CURLOPT_WRITEFUNCTION, write_response);
    curl_easy_setopt(curl.get(), CURLOPT_WRITEDATA, &response_data);
    curl_easy_setopt(curl.get(), CURLOPT_ERRORBUFFER, error);
    curl_easy_setopt(curl.get(), CURLOPT_NOPROGRESS, 0L);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFOFUNCTION, progress);
    curl_easy_setopt(curl.get(), CURLOPT_XFERINFODATA, cancelled.get());
    curl_easy_setopt(curl.get(), CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_1_1);
    curl_easy_setopt(curl.get(), CURLOPT_CONNECTTIMEOUT_MS, 15000L);
    curl_easy_setopt(curl.get(), CURLOPT_TIMEOUT_MS, 60000L);
    curl_easy_setopt(curl.get(), CURLOPT_NOSIGNAL, 1L);
    result = curl_easy_perform(curl.get());
    response = std::move(response_data.body);
    curl_easy_getinfo(curl.get(), CURLINFO_RESPONSE_CODE, &status);
    if (result == CURLE_OK && status < 500)
      break;
  }
  if (result != CURLE_OK)
    throw metasequoia::voice::VoiceError(
        std::string("Voice HTTP request failed: ") +
        (error[0] ? error : curl_easy_strerror(result)));
  if (status < 200 || status >= 300)
    throw metasequoia::voice::VoiceError("Voice HTTP status " +
                                         std::to_string(status));
  return metasequoia::voice::parse_transcription(response);
}
} // namespace msime::windows

#include "VoiceSessionPolicy.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("voice session policy failed at line " + std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)

constexpr std::size_t kRate = 16000;
} // namespace

int main() {
  try {
    // The batch buffer is the shared upload budget, about 655 s, not a minute. A 60 s cap used to discard every longer recording outright.
    REQUIRE(voice_batch_sample_limit == batch_capture_sample_limit);
    REQUIRE(voice_batch_sample_limit > kRate * 600);
    REQUIRE(voice_batch_sample_limit < batch_upload_sample_limit);
    const auto minute = voice_batch_capture(kRate * 60, 3200, voice_batch_sample_limit);
    REQUIRE(minute.keep == 3200 && !minute.full);

    // Below the limit everything is kept and the recording goes on.
    const auto early = voice_batch_capture(0, 3200, 10000);
    REQUIRE(early.keep == 3200 && !early.full);
    // The callback that reaches the limit keeps what fits and ends the recording; it is submitted, not thrown away.
    const auto edge = voice_batch_capture(9000, 3200, 10000);
    REQUIRE(edge.keep == 1000 && edge.full);
    const auto exact = voice_batch_capture(6800, 3200, 10000);
    REQUIRE(exact.keep == 3200 && exact.full);
    // Callbacks that arrive before the control thread stops the capture add nothing.
    const auto late = voice_batch_capture(10000, 3200, 10000);
    REQUIRE(late.keep == 0 && late.full);
    const auto empty = voice_batch_capture(0, 0, 10000);
    REQUIRE(empty.keep == 0 && !empty.full);

    // Starting: a disabled voice input stays silent; every other refusal says why, in MSIME-Windows' words.
    REQUIRE(voice_start_verdict({false, false, "", "", "", ""}).check == VoiceStartCheck::Disabled);
    REQUIRE(voice_start_verdict({false, false, "", "", "", ""}).message.empty());
    const auto no_token = voice_start_verdict({true, true, "", "wss://synthetic", "", "synthetic"});
    REQUIRE(no_token.check == VoiceStartCheck::Rejected);
    REQUIRE(no_token.message == voice_missing_token_message);
    REQUIRE(voice_start_verdict({true, false, "", "https://synthetic", "m", ""}).message ==
            voice_missing_token_message);
    REQUIRE(voice_start_verdict({true, true, "t", "wss://synthetic", "", ""}).message ==
            voice_doubao_start_message);
    REQUIRE(voice_start_verdict({true, true, "t", "", "", "r"}).message ==
            voice_doubao_start_message);
    REQUIRE(voice_start_verdict({true, false, "t", "", "m", ""}).message ==
            voice_missing_endpoint_message);
    REQUIRE(voice_start_verdict({true, false, "t", "https://synthetic", "", ""}).message ==
            voice_missing_model_message);
    // Doubao needs no model name, batch providers need no resource id.
    REQUIRE(voice_start_verdict({true, true, "t", "wss://synthetic", "", "r"}).check ==
            VoiceStartCheck::Ready);
    REQUIRE(voice_start_verdict({true, false, "t", "https://synthetic", "m", ""}).check ==
            VoiceStartCheck::Ready);
    REQUIRE(voice_missing_token_message.find("API Token") != std::string_view::npos);
    REQUIRE(voice_microphone_start_message == "无法启动麦克风。");
    REQUIRE(voice_capture_interrupted_message == "录音中断，请重试。");
    // The settings page, not a config file, is where these fields are edited here.
    REQUIRE(voice_doubao_start_message.find("config.toml") == std::string_view::npos);

    // A failed batch recognition shows the provider's sentence, not a generic line.
    const CloudAsrError status("Voice HTTP status 401", "语音识别失败：synthetic key rejected（code 401）");
    REQUIRE(voice_recognition_failure(status) == "语音识别失败：synthetic key rejected（code 401）");
    const CloudAsrError blank("Voice HTTP status 500", "");
    REQUIRE(voice_recognition_failure(blank) == std::string(voice_recognition_failed_message));
    const std::runtime_error other("synthetic");
    REQUIRE(voice_recognition_failure(other) == std::string(voice_recognition_failed_message));

    // Space lock shows the confirm and cancel buttons on a native recording only.
    REQUIRE(voice_lock_shows_actions(true, false));
    REQUIRE(!voice_lock_shows_actions(true, true));
    REQUIRE(!voice_lock_shows_actions(false, false));
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}

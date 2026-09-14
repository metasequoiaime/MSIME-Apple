#include "VoiceProviders.h"
#include <cassert>
#include <type_traits>

int main() {
    using namespace msime::voice;
    static_assert(std::is_same_v<decltype(&recognize_cloud_asr), decltype(&msime::windows::recognize_cloud_asr)>);
    assert(normalize_voice_provider("CLOUD") == "siliconflow");
    assert(is_doubao_asr_provider("DOUBAO"));
    assert(!is_doubao_asr_provider("openai"));
    assert(resolved_asr_endpoint("openai", default_asr_endpoint("doubao")) == default_asr_endpoint("openai"));
    assert(resolved_asr_endpoint("doubao", default_asr_endpoint("groq")) == default_asr_endpoint("doubao"));
    assert(default_asr_model("groq") == "whisper-large-v3-turbo");
    assert(default_polish_model("openai") == "gpt-4o-mini");
    auto cancelled = std::make_shared<std::atomic_bool>(true);
    bool rejected = false;
    try { recognize_cloud_asr({0.0f}, "openai", "https://example.invalid/asr", "fixture", "fixture", "en", cancelled); }
    catch (const std::exception &) { rejected = true; }
    assert(rejected);
}

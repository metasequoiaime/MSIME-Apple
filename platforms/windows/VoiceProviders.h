#pragma once

#include <string>
#include <string_view>

namespace msime::windows {
std::string normalize_voice_provider(std::string_view provider);
std::string default_asr_endpoint(std::string_view provider);
std::string default_asr_model(std::string_view provider);
bool is_doubao_asr_provider(std::string_view provider,
                            std::string_view endpoint = {});
}

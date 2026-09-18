#include "ProviderToken.h"

#include <iostream>
#include <stdexcept>

namespace {
[[noreturn]] void fail(int line) {
  throw std::runtime_error("provider token test failed at line " +
                           std::to_string(line));
}
#define require(value) do { if (!(value)) fail(__LINE__); } while (false)
} // namespace

int main() {
  try {
    const auto input = nlohmann::json{
        {"asr_tokens", {{"openai", "slot-key"}, {"groq", "other-key"}}},
        {"asr_token", "flat-key"}};
    require(msime::windows::provider_token(input, "asr_tokens", "asr_token",
                                           "OPENAI") == "slot-key");
    require(msime::windows::provider_token(input, "asr_tokens", "asr_token",
                                           "Groq") == "other-key");
    require(msime::windows::provider_token(input, "asr_tokens", "asr_token",
                                           "siliconflow") == "flat-key");
    const auto placeholders = nlohmann::json{
        {"asr_tokens", {{"openai", "<YOUR_ASR_TOKEN_OPENAI>"}}},
        {"asr_token", "FAKESECRET_fallback"}};
    require(msime::windows::provider_token(placeholders, "asr_tokens",
                                           "asr_token", "openai").empty());
    require(msime::windows::provider_token(placeholders, "asr_tokens",
                                           "asr_token", "groq").empty());
    std::cout << "Provider token lookup is case insensitive\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

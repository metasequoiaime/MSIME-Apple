#include "../src/voice/VoiceProviderOptions.h"

#include <cassert>
#include <stdexcept>
#include <string>

using Json = nlohmann::json;
using msime::linux_host::voice_provider_options;

int main() {
  // An edited built-in prompt reaches the provider, which polishes with it as the Windows service does.
  auto options = voice_provider_options(Json{{"voice_input", {{"polish_prompt_id", "cleanup"}, {"polish_prompt", "只修正错别字"}, {"polish_enabled", true}}}});
  assert(options.at("polish_prompt") == "只修正错别字");
  assert(options.at("polish_prompt_id") == "cleanup");
  assert(options.at("polish_enabled") == true);
  assert(!options.contains("polish_prompt_custom_1"));

  // The selected custom slot is still forwarded; the other slots stay home.
  options = voice_provider_options(Json{{"voice_input", {{"polish_prompt_id", "custom_2"}, {"polish_prompt_custom_2", "二号"}, {"polish_prompt_custom_3", "三号"}}}});
  assert(options.at("polish_prompt_custom_2") == "二号");
  assert(!options.contains("polish_prompt_custom_3"));
  assert(!options.contains("polish_prompt"));

  // Legacy "custom" is slot one; empty prompts are not sent.
  options = voice_provider_options(Json{{"voice_input", {{"polish_prompt_id", "custom"}, {"polish_prompt_custom_1", "一号"}, {"polish_prompt", ""}}}});
  assert(options.at("polish_prompt_custom_1") == "一号");
  assert(!options.contains("polish_prompt"));

  // Short strings are cut on a UTF-8 boundary, never through a character.
  std::string long_device(170, 'a');
  for (int i = 0; i < 200; ++i) long_device += "字";
  options = voice_provider_options(Json{{"voice_input", {{"capture_device", long_device}}}});
  const auto device = options.at("capture_device").get<std::string>();
  assert(device.size() <= 512 && device.size() == 170 + 114 * 3);
  assert(Json(device).dump().size() > 0);

  // Unknown auth modes, non-boolean flags and the hold-to-lock gesture flag.
  options = voice_provider_options(Json{{"voice_input", {{"doubao_auth_mode", "other"}, {"sound_enabled", "yes"}, {"hotkey_hold_space_lock", true}}}});
  assert(!options.contains("doubao_auth_mode"));
  assert(!options.contains("sound_enabled"));
  assert(options.at("hotkey_hold_space_lock") == true);

  // An oversized prompt is refused rather than truncated.
  bool refused = false;
  try {
    voice_provider_options(Json{{"voice_input", {{"polish_prompt", std::string(8193, 'x')}}}});
  } catch (const std::runtime_error &) {
    refused = true;
  }
  assert(refused);
  assert(voice_provider_options(Json::object()).empty());
  return 0;
}

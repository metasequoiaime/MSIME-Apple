#include "../VoiceControlMessage.h"
#include <iostream>

int main() {
  using namespace msime::windows;
  const VoiceControlMessage input{VoiceControlCommand::Start, 7, 11, 13};
  const auto encoded = encode_voice_control(input);
  if (!encoded) return 1;
  const auto decoded = decode_voice_control(*encoded);
  if (!decoded || decoded->client_id != 7 || decoded->activation_epoch != 11 ||
      decoded->generation != 13 || decoded->command != VoiceControlCommand::Start)
    return 1;
  if (decode_voice_control(L"MSIME_VOICE|2|0|11|13") ||
      decode_voice_control(L"MSIME_VOICE|9|7|11|13")) return 1;
  std::cout << "Voice control codec: valid shape and identity fields\n";
}

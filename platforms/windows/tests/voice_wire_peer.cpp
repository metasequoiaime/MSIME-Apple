// Portable subprocess fixture: real codec/dispatcher, synthetic capture only.
// Length-prefixed stdio is test transport, NOT the authenticated Windows pipe.
#include "../src/VoiceControllerDispatch.h"
#include <array>
#include <iostream>

int main(int argc, char **argv) {
  using namespace msime::windows;
  using namespace FanyImeVoiceController;
  const std::string mode = argc == 2 ? argv[1] : "ok";
  auto channel = std::make_shared<VoiceControllerChannel>();
  std::shared_ptr<VoiceReviewResult> result;
  VoiceControllerDispatch dispatcher({
      []() -> std::optional<FocusLease> {
        return FocusLease{{77, {1, 2, 3}}, 4, 5};
      },
      [](const FocusLease &) { return true; },
      [&](std::string_view language) {
        if (language != "en-US")
          return std::shared_ptr<VoiceReviewResult>{};
        result = std::make_shared<VoiceReviewResult>();
        result->level(0.5f);
        return result;
      },
      [](const auto &capture) { capture->recognizing(); return true; },
      [](const auto &capture) { capture->cancel(); return true; }});
  unsigned polls = 0;
  while (true) {
    std::array<unsigned char, 4> prefix{};
    if (!std::cin.read(reinterpret_cast<char *>(prefix.data()), 4))
      return std::cin.eof() ? 0 : 1;
    uint32_t length = 0;
    for (unsigned i = 0; i < 4; ++i)
      length |= uint32_t{prefix[i]} << (8 * i);
    if (length < sizeof(Request) || length > sizeof(Request) + MaxLanguageBytes)
      return 2;
    std::vector<uint8_t> bytes(length);
    if (!std::cin.read(reinterpret_cast<char *>(bytes.data()), length))
      return 3;
    const auto request = decode_voice_controller_request(bytes);
    if (!request)
      return 4;
    VoiceControllerResponse response;
    if (request->header.operation == Operation::Hello) {
      response.header.request_id = request->header.request_id;
    } else {
      if (request->header.operation == Operation::Poll && result) {
        if (mode == "disconnect") return 0;
        if (mode == "cancelled") result->cancel();
        else if (mode == "failed") result->fail();
        else if (++polls == 1) result->processing();
        else result->complete("synthetic \xe6\xb5\x8b\xe8\xaf\x95 \xf0\x9f\x8c\xb2");
      }
      response = dispatcher.dispatch(channel, *request);
      if (request->header.operation == Operation::Poll) {
        if (mode == "wrong-id") ++response.header.request_id;
        if (mode == "wrong-session") ++response.header.session_id;
      }
    }
    const auto encoded = encode_voice_controller_reply(response.header, response.text);
    if (!encoded) return 5;
    for (unsigned i = 0; i < 4; ++i)
      prefix[i] = static_cast<unsigned char>(encoded->size() >> (8 * i));
    std::cout.write(reinterpret_cast<const char *>(prefix.data()), 4);
    std::cout.write(reinterpret_cast<const char *>(encoded->data()), encoded->size());
    std::cout.flush();
    if (!std::cout) return 6;
  }
}

#include "../src/voice/VoiceControllerProtocol.h"
#include <cassert>

int main() {
  using namespace FanyImeVoiceController;
  using namespace msime::windows;
  Request header;
  header.controller_id = (uint64_t{7} << 32) | 1;
  header.request_id = 1;
  const auto packet = [&](std::string_view language) {
    std::vector<uint8_t> bytes(sizeof(header) + language.size());
    std::memcpy(bytes.data(), &header, sizeof(header));
    if (!language.empty()) std::memcpy(bytes.data() + sizeof(header), language.data(), language.size());
    return bytes;
  };
  auto hello = packet("");
  assert(hello[0] == 'M' && hello[1] == 'V' && hello[2] == 'C' && hello[3] == '2');
  assert(decode_voice_controller_request(hello));
  for (size_t count = 0; count < sizeof(header); ++count)
    assert(!decode_voice_controller_request(std::vector<uint8_t>(hello.begin(), hello.begin() + count)));
  hello.push_back(0);
  assert(!decode_voice_controller_request(hello));
  header.operation = Operation::Start;
  header.language_bytes = 5;
  const auto start = decode_voice_controller_request(packet("zh-CN"));
  assert(start && start->language == "zh-CN");
  assert(!decode_voice_controller_request(packet("zh\nCN")));
  assert(!decode_voice_controller_request(packet(std::string("zh\0CN", 5))));
  header.language_bytes = 2;
  assert(!decode_voice_controller_request(packet("\xc0\x80")));
  assert(!decode_voice_controller_request(packet("\xc2\x85")));
  header.version = 1;
  assert(!decode_voice_controller_request(packet("en")));
  Reply reply;
  reply.request_id = 1;
  reply.session_id = 2;
  reply.phase = Phase::Complete;
  assert(encode_voice_controller_reply(reply, "fixture"));
  assert(encode_voice_controller_reply(reply, "\xf0\x9f\x98\x80"));
  for (const auto invalid : {"\xed\xa0\x80", "\xf4\x90\x80\x80", "\xf0\x9f", "\x80"})
    assert(!encode_voice_controller_reply(reply, invalid));
  assert(!encode_voice_controller_reply(reply, std::string(MaxTextBytes + 1, 'x')));
  assert(encode_voice_controller_reply(reply, std::string(MaxTextBytes, 'x')));
  assert(!encode_voice_controller_reply(reply, std::string("ok\0tail", 7)));
  std::string boundary(MaxTextBytes - 1, 'x');
  boundary.push_back('\0');
  assert(!encode_voice_controller_reply(reply, boundary));
  reply.status = Status::Denied;
  assert(!encode_voice_controller_reply(reply, "fixture"));
  assert(encode_voice_controller_reply(reply));
}

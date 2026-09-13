#include "ReplyCodec.h"
#include "ipc_negotiation.h"
#include <array>
#include <cstring>
#include <iostream>
#include <stdexcept>

using namespace msime::windows;
namespace {
void require(bool condition) {
  if (!condition)
    throw std::runtime_error("Windows reply codec assertion failed");
}
std::u16string payload(const EncodedReply &reply) {
  require(static_cast<bool>(reply));
  std::u16string result;
  for (const auto c : reply.packet.candidate_string) {
    if (!c)
      break;
    result += static_cast<char16_t>(c);
  }
  return result;
}
void error(const EncodedReply &reply, ReplyError expected) {
  require(!reply && reply.error == expected && reply.packet.request_id == 0 &&
          reply.packet.msg_type == 0);
  for (const auto c : reply.packet.candidate_string)
    require(c == 0);
}
} // namespace
int main() {
  try {
    {
      require(!ui_complete_selection(""));
      require(!ui_complete_selection(std::string(200, 'a')));
      require(!ui_complete_selection(std::string("a\0b", 3)));
      require(!ui_complete_selection(std::string(1, static_cast<char>(0xff))));
      const auto complete = ui_complete_selection("中😀");
      require(complete && !complete->before_trigger &&
              complete->worker.size() == 404);
      require(complete->worker[0] ==
              FanyImeWorkerReplyType::CommitCurCandidate);
      require(complete->worker[4] == 0x2d && complete->worker[5] == 0x4e);
      require(complete->worker[6] == 0x3d && complete->worker[7] == 0xd8);
      require(complete->worker[8] == 0 && complete->worker[9] == 0xde);
      for (size_t i = 10; i < complete->worker.size(); ++i)
        require(complete->worker[i] == 0);
      const auto partial = ui_partial_selection("hao", "你", "你好");
      require(partial && partial->before_trigger);
      auto expected_partial =
          *wire_bytes(partial_selection(1, "hao", "你", "你好"));
      expected_partial[8] = 0;
      require(*partial->before_trigger == expected_partial);
      require(partial->worker[0] == FanyImeWorkerReplyType::CommitCurCandidate);
      for (size_t i = 1; i < partial->worker.size(); ++i)
        require(partial->worker[i] == 0);
      require(!ui_partial_selection("", "你", "你好"));
      require(!ui_partial_selection("hao", "你\t", "你好"));
      const auto rejected = ui_rejected_selection();
      require(rejected.before_trigger &&
              rejected.before_trigger->at(0) == FanyImeReplyType::OutofRange);
      for (size_t i = 1; i < rejected.before_trigger->size(); ++i)
        require(rejected.before_trigger->at(i) == 0);
    }
    for (auto [navigation, type] :
         std::vector<std::pair<NavigationReply, uint32_t>>{
             {NavigationReply::Ignored, FanyImeReplyType::NavigationIgnored},
             {NavigationReply::PreviousCandidate,
              FanyImeReplyType::MoveSelectionPrevious},
             {NavigationReply::NextCandidate,
              FanyImeReplyType::MoveSelectionNext},
             {NavigationReply::PreviousPage,
              FanyImeReplyType::MovePagePrevious},
             {NavigationReply::NextPage, FanyImeReplyType::MovePageNext}}) {
      const auto reply = navigation_reply(77, navigation);
      require(reply && reply.packet.msg_type == type && payload(reply).empty());
      const auto bytes = *wire_bytes(reply);
      require(bytes[0] == type && bytes[8] == 77);
      for (size_t i = 16; i < bytes.size(); ++i)
        require(bytes[i] == 0);
      error(navigation_reply(0, navigation), ReplyError::InvalidRequest);
      error(navigation_reply(FANY_IME_NO_REQUEST_ID, navigation),
            ReplyError::InvalidRequest);
    }
    error(navigation_reply(77, static_cast<NavigationReply>(99)),
          ReplyError::InvalidFields);
    require(!focus_ready_bytes(0));
    for (const auto &[mode, opcode] :
         std::vector<std::pair<WorkerMode, uint32_t>>{
             {WorkerMode::English, FanyImeWorkerReplyType::SwitchToEnglish},
             {WorkerMode::Chinese, FanyImeWorkerReplyType::SwitchToChinese},
             {WorkerMode::AsciiPunctuation,
              FanyImeWorkerReplyType::SwitchToPuncEn},
             {WorkerMode::ChinesePunctuation,
              FanyImeWorkerReplyType::SwitchToPuncCn},
             {WorkerMode::Fullwidth, FanyImeWorkerReplyType::SwitchToFullwidth},
             {WorkerMode::Halfwidth,
              FanyImeWorkerReplyType::SwitchToHalfwidth}}) {
      const auto bytes = worker_mode_bytes(mode);
      require(bytes && bytes->size() == 404 && bytes->at(0) == opcode);
      for (size_t i = 1; i < bytes->size(); ++i)
        require(bytes->at(i) == 0);
    }
    require(!worker_mode_bytes(static_cast<WorkerMode>(99)));
    {
      const auto frames = voice_composition_bytes(
          FanyImeWorkerReplyType::UpdateVoiceComposition, L"你好😀", 7);
      require(frames && frames->size() == 1 && frames->front().size() == 404);
      require(frames->front()[0] == FanyImeWorkerReplyType::UpdateVoiceComposition);
      std::array<wchar_t, FanyImeVoiceCompositionPipe::kPacketChars> payload{};
      std::memcpy(payload.data(), frames->front().data() + 4,
                  frames->front().size() - 4);
      const auto parsed = FanyImeVoiceCompositionPipe::ParseFrame(payload.data());
      require(parsed.valid && parsed.first && parsed.last && parsed.generation == 7 &&
              parsed.chunk == L"你好😀");
      require(!voice_composition_bytes(
          FanyImeWorkerReplyType::UpdateVoiceComposition, L"", 0));
      require(!voice_composition_bytes(FanyImeWorkerReplyType::PipeReady, L"x", 7));
    }
    for (const auto &example : std::vector<std::pair<uint64_t, std::string>>{
             {1, "1"},
             {77, "77"},
             {4294967296ULL, "4294967296"},
             {UINT64_MAX, "18446744073709551615"}}) {
      const auto fence = focus_ready_bytes(example.first);
      require(fence &&
              fence->size() == sizeof(FanyImeNamedpipeDataToTsfWorkerThread));
      require(fence->at(0) == FanyImeWorkerReplyType::FocusSessionReady);
      for (size_t i = 1; i < 4; ++i)
        require(fence->at(i) == 0);
      for (size_t i = 0; i < example.second.size(); ++i) {
        require(fence->at(4 + 2 * i) ==
                static_cast<uint8_t>(example.second[i]));
        require(fence->at(5 + 2 * i) == 0);
      }
      for (size_t i = 4 + example.second.size() * 2; i < fence->size(); ++i)
        require(fence->at(i) == 0);
    }
    for (auto role :
         {FanyImePipeRole::ToTsf, FanyImePipeRole::ToTsfWorkerThread}) {
      auto ready = pipe_ready_bytes(role);
      require(ready &&
              ready->size() ==
                  (role == FanyImePipeRole::ToTsf
                       ? sizeof(FanyImeNamedpipeDataToTsf)
                       : sizeof(FanyImeNamedpipeDataToTsfWorkerThread)));
      require(ready->at(0) == 9);
      for (size_t i = 1; i < ready->size(); ++i)
        require(ready->at(i) == 0);
    }
    require(!pipe_ready_bytes(FanyImePipeRole::Main));
    require(!pipe_ready_bytes(99));
    auto hello = FanyImeProtocol::Hello(9, 0x0102030405060708ULL);
    auto protocol = FanyImeProtocol::Negotiate(
        hello, FanyImeProtocol::RequiredCapabilities);
    auto packet = FanyImeProtocol::Reply(hello, protocol);
    auto ack = protocol_reply_bytes(packet);
    require(ack && ack->at(0) == FanyImeReplyType::ProtocolReady &&
            ack->at(8) == 8 && ack->at(15) == 1 && ack->at(20) == 3);
    require(ack->at(24) == 0x50 && ack->at(25) == 0x49 && ack->at(26) == 0x53 &&
            ack->at(27) == 0x4d);
    for (size_t i = 4; i < 8; ++i)
      require(ack->at(i) == 0);
    for (size_t i = 28; i < ack->size(); ++i)
      require(ack->at(i) == 0);
    hello.point[1] |= FanyImeProtocol::FramedVoice;
    protocol = FanyImeProtocol::Negotiate(
        hello, FanyImeProtocol::RequiredCapabilities);
    require(!protocol.accepted);
    ack = protocol_reply_bytes(FanyImeProtocol::Reply(hello, protocol));
    require(ack && ack->at(0) == FanyImeReplyType::ProtocolMismatch);
    packet.request_id = 0;
    require(!protocol_reply_bytes(packet));
    packet.request_id = FANY_IME_NO_REQUEST_ID;
    require(!protocol_reply_bytes(packet));
    packet.request_id = 1;
    packet.msg_type = FanyImeReplyType::Normal;
    require(!protocol_reply_bytes(packet));
    auto full = candidate_commit(23, "你好😀");
    require(full.packet.msg_type == FanyImeReplyType::Normal &&
            full.packet.request_id == 23);
    require(payload(full) == u"你好😀");
    auto bytes = wire_bytes(exact_commit(0x0102030405060708ULL, "中😀"));
    require(bytes.has_value() &&
            bytes->at(0) == FanyImeReplyType::CommitExactText);
    require(bytes->at(4) == 0 && bytes->at(5) == 0 && bytes->at(6) == 0 &&
            bytes->at(7) == 0);
    require(bytes->at(8) == 8 && bytes->at(15) == 1);
    require(bytes->at(16) == 0x2D && bytes->at(17) == 0x4E &&
            bytes->at(18) == 0x3D && bytes->at(19) == 0xD8 &&
            bytes->at(20) == 0 && bytes->at(21) == 0xDE);
    for (size_t i = 22; i < bytes->size(); ++i)
      require(bytes->at(i) == 0);
    require(!wire_bytes(exact_commit(0, "中")).has_value());
    auto exact = exact_commit(24, "你好，");
    require(exact.packet.msg_type == FanyImeReplyType::CommitExactText &&
            payload(exact) == u"你好，");
    auto preedit = preedit_reply(25, "ni hao");
    require(preedit.packet.msg_type == FanyImeReplyType::Preedit &&
            payload(preedit) == u"ni hao");
    auto partial = partial_selection(26, "hao", "你", "你好");
    require(partial.packet.msg_type == FanyImeReplyType::NeedToCreateWord &&
            payload(partial) == u"hao\t你\t你好");
    auto page = uiless_reply(27, "ni hao", {"你好", "拟好"}, 1);
    require(page.packet.msg_type == FanyImeReplyType::UiLessComposition &&
            payload(page) == u"ni hao\t你好,拟好\t1");
    require(payload(uiless_reply(28, "", {}, 0)) == u"\t\t0");
    require(ignored_reply(29).packet.msg_type ==
            FanyImeReplyType::NavigationIgnored);
    require(payload(exact_commit(30, std::string(199, 'a'))).size() == 199);
    error(exact_commit(30, std::string(200, 'a')), ReplyError::TooLong);
    require(payload(exact_commit(31, std::string(197, 'a') + "😀")).size() ==
            199);
    error(exact_commit(31, std::string(198, 'a') + "😀"), ReplyError::TooLong);
    std::string chinese;
    for (int i = 0; i < 199; ++i)
      chinese += "中";
    require(payload(candidate_commit(32, chinese)).size() == 199);
    error(candidate_commit(32, chinese + "中"), ReplyError::TooLong);
    for (const auto &invalid :
         {std::string("\x80"), std::string("\xc0\xaf"),
          std::string("\xe0\x80\xaf"), std::string("\xed\xa0\x80"),
          std::string("\xf4\x90\x80\x80"), std::string("\xf0\x9f"),
          std::string("\xe4x")})
      error(exact_commit(33, invalid), ReplyError::InvalidUtf8);
    error(exact_commit(34, std::string("a\0b", 3)), ReplyError::EmbeddedNul);
    error(exact_commit(0, "中"), ReplyError::InvalidRequest);
    error(exact_commit(FANY_IME_NO_REQUEST_ID, "中"),
          ReplyError::InvalidRequest);
    error(partial_selection(35, "", "你", "你"), ReplyError::InvalidFields);
    error(partial_selection(35, "hao", "你\t", "你"),
          ReplyError::InvalidFields);
    error(uiless_reply(36, "a\tb", {"中"}, 0), ReplyError::InvalidFields);
    error(uiless_reply(36, "a", {"a,b"}, 0), ReplyError::InvalidFields);
    error(uiless_reply(36, "a", {"中"}, 1), ReplyError::InvalidFields);
    error(uiless_reply(36, "a", std::vector<std::string>(10, "中"), 0),
          ReplyError::InvalidFields);
    error(uiless_reply(36, std::string(199, 'a'), {"中"}, 0),
          ReplyError::TooLong);
    std::cout
        << "Windows reply codec: legacy layouts, Unicode and bounds passed\n";
  } catch (const std::exception &exception) {
    std::cerr << exception.what() << '\n';
    return 1;
  }
}

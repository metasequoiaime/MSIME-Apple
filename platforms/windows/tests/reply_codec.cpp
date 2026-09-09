#include "ReplyCodec.h"
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

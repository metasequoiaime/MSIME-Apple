#include "ReplyComposer.h"
#include <iostream>
#include <stdexcept>

using namespace msime::windows;
using Json = nlohmann::json;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Windows reply composer assertion failed");
}
template <class F> void rejected(F action) {
  bool failed = false;
  try {
    action();
  } catch (const std::exception &) {
    failed = true;
  }
  require(failed);
}
KeyResult result(uint64_t request, const char *raw, const char *display,
                 Json commit = nullptr) {
  return {42,
          7,
          request,
          true,
          {{"handled", true},
           {"commit", commit},
           {"view",
            {{"session", 13},
             {"editing_text", raw},
             {"preedit", display},
             {"candidates", Json::array()}}}}};
}
std::u16string payload(const PendingReply &reply) {
  require(reply.encoded.has_value() && static_cast<bool>(*reply.encoded));
  std::u16string text;
  for (auto c : reply.encoded->packet.candidate_string) {
    if (!c)
      break;
    text += static_cast<char16_t>(c);
  }
  return text;
}
void confirm(ReplyComposer &composer) {
  composer.confirm_delivery(42, 7, composer.pending().source.request_id);
}
} // namespace
int main() {
  try {
    FanyImeNamedpipeData edge_packet{};
    edge_packet.event_type = FanyImePipeEventType::KeyEvent;
    edge_packet.keycode = 0xDB;
    edge_packet.wch = '[';
    require(word_character_edge(edge_packet, WordCharacterBinding::Brackets) == MSIME_FIRST_HAN);
    require(!word_character_edge(edge_packet, WordCharacterBinding::Disabled));
    require(!word_character_edge(edge_packet, WordCharacterBinding::MinusEqual));
    for (uint32_t modifiers : {1u, 2u, 4u, 8u}) {
      edge_packet.modifiers_down = modifiers;
      require(!word_character_edge(edge_packet, WordCharacterBinding::Brackets));
    }
    edge_packet.modifiers_down = FanyImePipeFlags::UiLess;
    require(word_character_edge(edge_packet, WordCharacterBinding::Brackets) == MSIME_FIRST_HAN);
    edge_packet.wch = '{';
    require(!word_character_edge(edge_packet, WordCharacterBinding::Brackets));
    edge_packet.keycode = 0x6D;
    edge_packet.wch = '-';
    require(!word_character_edge(edge_packet, WordCharacterBinding::MinusEqual));
    rejected([&] { word_character_edge(edge_packet, static_cast<WordCharacterBinding>(99)); });
    ReplyComposer empty_fallback(42, 7);
    require(payload(empty_fallback.stage(result(1, "", "", ""),
        ReplyPath::CandidatePunctuationFallback)).empty());
    confirm(empty_fallback);
    for (bool fallback : {false, true}) {
      ReplyComposer prefixed(42, 7);
      prefixed.stage(result(1, "hao", "hao", "你"), ReplyPath::Selection);
      confirm(prefixed);
      const auto &reply =
          prefixed.stage(result(2, "", "", fallback ? "A" : "好"),
                         fallback ? ReplyPath::CandidatePunctuationFallback
                                  : ReplyPath::Punctuation);
      require(reply.encoded && static_cast<bool>(*reply.encoded));
      require(reply.encoded->packet.msg_type ==
              (fallback ? FanyImeReplyType::Normal
                        : FanyImeReplyType::CommitExactText));
      require(reply.source.transition.at("commit") == (fallback ? "A" : "好"));
      require(reply.next_prefix.empty() && prefixed.selected_prefix() == "你");
      require(payload(reply) == (fallback ? u"你A" : u"你好"));
      confirm(prefixed);
      require(prefixed.selected_prefix().empty());
    }
    ReplyComposer composer(42, 7);
    auto first = result(1, "haoma", "hao ma", "你");
    require(payload(composer.stage(first, ReplyPath::Selection)) ==
            u"haoma\t你\t你hao ma");
    require(composer.selected_prefix().empty());
    auto bytes = wire_bytes(*composer.pending().encoded);
    require(bytes ==
            wire_bytes(*composer.pending()
                            .encoded)); // Retry does not advance Engine/prefix.
    rejected([&] { composer.stage(first, ReplyPath::Selection); });
    rejected([&] { composer.confirm_delivery(42, 6, 1); });
    confirm(composer);
    require(composer.selected_prefix() == "你");
    for (auto [path, type] : std::vector<std::pair<ReplyPath, uint32_t>>{
             {ReplyPath::IgnoredNavigation,
              FanyImeReplyType::NavigationIgnored},
             {ReplyPath::PreviousCandidate,
              FanyImeReplyType::MoveSelectionPrevious},
             {ReplyPath::NextCandidate, FanyImeReplyType::MoveSelectionNext},
             {ReplyPath::PreviousPage, FanyImeReplyType::MovePagePrevious},
             {ReplyPath::NextPage, FanyImeReplyType::MovePageNext}}) {
      const auto &navigation =
          composer.stage(result(91, "haoma", "hao ma"), path);
      require(navigation.encoded->packet.msg_type == type &&
              payload(navigation).empty());
      rejected([&, navigation_path = path] {
        composer.stage(result(92, "haoma", "hao ma"), navigation_path);
      });
      confirm(composer);
      require(composer.selected_prefix() == "你");
      auto page = result(93, "haoma", "hao ma");
      page.transition["view"]["candidates"] =
          Json::array({{{"text", "好"}, {"highlighted", false}},
                       {{"text", "号"}, {"highlighted", true}}});
      const auto &uiless = composer.stage(page, path, true);
      require(uiless.encoded->packet.msg_type ==
              FanyImeReplyType::UiLessComposition);
      require(payload(uiless).find(u"你hao ma\t") == 0);
      confirm(composer);
      require(composer.selected_prefix() == "你");
      const auto &invalid =
          composer.stage(result(94, "haoma", "hao ma", "x"), path);
      require(invalid.encoded && !*invalid.encoded);
      rejected([&] { confirm(composer); });
      composer.cancel();
      composer.stage(first, ReplyPath::Selection);
      confirm(composer);
    }
    require(payload(composer.stage(result(2, "haoma", "hao ma"),
                                   ReplyPath::Composition)) == u"你hao ma");
    confirm(composer);
    require(payload(composer.stage(result(3, "ma", "ma", "好"),
                                   ReplyPath::Selection)) ==
            u"ma\t你好\t你好ma");
    confirm(composer);
    const auto &complete =
        composer.stage(result(4, "", "", "吗"), ReplyPath::Selection);
    require(complete.encoded->packet.msg_type == FanyImeReplyType::Normal &&
            payload(complete) == u"你好吗");
    confirm(composer);
    require(composer.selected_prefix().empty());
    composer.stage(first, ReplyPath::Selection);
    confirm(composer);
    const auto &punctuation =
        composer.stage(result(5, "", "", "好吗，"), ReplyPath::Punctuation);
    require(punctuation.encoded->packet.msg_type ==
                FanyImeReplyType::CommitExactText &&
            payload(punctuation) == u"你好吗，");
    confirm(composer);
    composer.stage(first, ReplyPath::Selection);
    confirm(composer);
    require(!composer
                 .stage(result(6, "", "", "haoma"), ReplyPath::LocalCommit,
                        false, "你haoma")
                 .encoded);
    confirm(composer);
    require(composer.selected_prefix().empty());
    composer.stage(first, ReplyPath::Selection);
    confirm(composer);
    require(!composer.stage(result(0, "", ""), ReplyPath::LocalCancel).encoded);
    confirm(composer);
    require(composer.selected_prefix().empty());
    auto stale = first;
    stale.activation_epoch = 8;
    rejected([&] { composer.stage(stale, ReplyPath::Selection); });
    auto page = result(7, "nihao", "ni hao");
    page.transition["view"]["candidates"] =
        Json::array({{{"text", "你好"}, {"highlighted", false}},
                     {{"text", "拟好"}, {"highlighted", true}}});
    require(payload(composer.stage(page, ReplyPath::Composition, true)) ==
            u"ni hao\t你好,拟好\t1");
    confirm(composer);
    auto too_long = result(8, "", "", std::string(200, 'x'));
    const auto &failed = composer.stage(too_long, ReplyPath::Selection);
    require(failed.encoded->error == ReplyError::TooLong &&
            failed.source.transition.at("commit") == std::string(200, 'x'));
    rejected([&] { confirm(composer); });
    rejected([&] { composer.stage(first, ReplyPath::Selection); });
    require(composer.pending().source.request_id == 8);
    composer.cancel();
    require(composer.selected_prefix().empty());
    rejected([&] { composer.pending(); });
    auto mismatch = result(9, "", "", "raw");
    require(composer.stage(mismatch, ReplyPath::LocalCommit, false, "different")
                .encoded->error == ReplyError::InvalidFields);
    require(composer.pending().source.transition.at("commit") == "raw");
    rejected([&] { confirm(composer); });
    composer.cancel();
    std::cout << "Windows reply composer: segmented prefix, confirmation and "
                 "failure retention passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

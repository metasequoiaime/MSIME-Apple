#include "ReplyComposer.h"
#include "PunctuationPolicy.h"
#include <stdexcept>

namespace msime::windows {
namespace {
std::optional<NavigationReply> navigation_for(ReplyPath path) {
  switch (path) {
  case ReplyPath::IgnoredNavigation:
    return NavigationReply::Ignored;
  case ReplyPath::PreviousCandidate:
    return NavigationReply::PreviousCandidate;
  case ReplyPath::NextCandidate:
    return NavigationReply::NextCandidate;
  case ReplyPath::PreviousPage:
    return NavigationReply::PreviousPage;
  case ReplyPath::NextPage:
    return NavigationReply::NextPage;
  default:
    return std::nullopt;
  }
}
} // namespace
ReplyComposer::ReplyComposer(uint64_t client, uint64_t epoch)
    : client_(client), epoch_(epoch) {
  if (!client || !epoch)
    throw std::invalid_argument("Invalid reply activation");
}
const PendingReply &
ReplyComposer::stage(const KeyResult &result, ReplyPath path, bool uiless,
                     std::optional<std::string> local_text) {
  if (pending_)
    throw std::logic_error(
        "Resolve the pending reply before dispatching another key");
  if (result.client_id != client_ || result.activation_epoch != epoch_)
    throw std::logic_error("Expired reply route");
  const auto &view = result.transition.at("view");
  const auto session = view.at("session").get<uint64_t>();
  if (!session || (session_ && session != session_))
    throw std::logic_error("Reply changed host session");
  const auto raw = view.at("editing_text").get<std::string>();
  const auto display = view.at("preedit").get<std::string>();
  const auto &commit = result.transition.at("commit");
  const auto delta =
      commit.is_null() ? std::string{} : commit.get<std::string>();
  PendingReply next{result, std::nullopt, prefix_};
  const auto invalid = [&] {
    next.encoded = EncodedReply{ReplyError::InvalidFields, {}};
  };
  switch (path) {
  case ReplyPath::LocalCancel:
    if (!delta.empty() || !raw.empty()) {
      invalid();
      break;
    }
    next.next_prefix.clear();
    break;
  case ReplyPath::NoReply:
    if (!delta.empty()) {
      invalid();
      break;
    }
    break;
  case ReplyPath::LocalCommit:
    // Legacy Enter inserts the prefix plus its local raw buffer. This is a
    // completion acknowledgement, not a second text insertion frame.
    if (!raw.empty() || !local_text || *local_text != prefix_ + delta)
      next.encoded = EncodedReply{ReplyError::InvalidFields, {}};
    else
      next.next_prefix.clear();
    break;
  case ReplyPath::Selection:
    if (!result.reply_expected) {
      invalid();
      break;
    }
    if (delta.empty())
      next.encoded = ignored_reply(result.request_id);
    else {
      const auto total = prefix_ + delta;
      if (!raw.empty()) {
        next.encoded =
            partial_selection(result.request_id, raw, total, total + display);
        next.next_prefix = total;
      } else {
        next.encoded = candidate_commit(result.request_id, total);
        next.next_prefix.clear();
      }
    }
    break;
  case ReplyPath::Punctuation:
    if (!result.reply_expected) {
      invalid();
      break;
    }
    if (delta.empty())
      next.encoded = ignored_reply(result.request_id);
    else {
      if (!raw.empty()) {
        invalid();
        break;
      }
      next.encoded = exact_commit(result.request_id, prefix_ + delta);
      next.next_prefix.clear();
    }
    break;
  case ReplyPath::CandidatePunctuationFallback:
    if (!result.reply_expected || !raw.empty()) {
      invalid();
      break;
    }
    next.encoded = candidate_commit(result.request_id, prefix_ + delta);
    next.next_prefix.clear();
    break;
  case ReplyPath::IgnoredNavigation:
  case ReplyPath::PreviousCandidate:
  case ReplyPath::NextCandidate:
  case ReplyPath::PreviousPage:
  case ReplyPath::NextPage:
  case ReplyPath::Composition:
    if (!delta.empty() || !result.reply_expected) {
      invalid();
      break;
    }
    if (!uiless) {
      const auto navigation = navigation_for(path);
      next.encoded = navigation
                         ? navigation_reply(result.request_id, *navigation)
                         : preedit_reply(result.request_id, prefix_ + display);
    } else {
      std::vector<std::string> candidates;
      size_t highlighted = 0;
      bool found_highlight = false;
      for (const auto &candidate : view.at("candidates")) {
        if (candidate.at("highlighted").get<bool>()) {
          if (found_highlight)
            throw std::logic_error("Ambiguous candidate highlight");
          highlighted = candidates.size();
          found_highlight = true;
        }
        candidates.push_back(candidate.at("text").get<std::string>());
      }
      if (!candidates.empty() && !found_highlight)
        throw std::logic_error("Missing candidate highlight");
      next.encoded = uiless_reply(result.request_id, prefix_ + display,
                                  candidates, highlighted);
    }
    break;
  }
  session_ = session;
  pending_ = std::move(next);
  return *pending_;
}
const PendingReply &ReplyComposer::pending() const {
  if (!pending_)
    throw std::logic_error("No pending reply");
  return *pending_;
}
const PendingReply &ReplyComposer::dispatch(
    ServerSession &session, const FanyImeNamedpipeData &packet, uint64_t epoch,
    ReplyPath path, bool uiless, std::optional<std::string> local_text) {
  if (pending_ || packet.client_id != client_ || epoch != epoch_)
    throw std::logic_error("Pending or expired Windows reply route");
  if (session_ && session.view().at("session").get<uint64_t>() != session_)
    throw std::logic_error("Reply changed host session");
  if (path == ReplyPath::LocalCommit && session.input_enabled()) {
    const auto action = translate_key(packet);
    const auto raw = session.view().at("editing_text").get<std::string>();
    // The TSF has already inserted its local text. Validate that observation
    // before MSIME_COMMIT_RAW can clear Engine state. The postflight check in
    // stage() remains necessary; never manufacture proof from Engine's result.
    if (action.kind != KeyKind::Command || action.value != MSIME_COMMIT_RAW ||
        !local_text || *local_text != prefix_ + raw)
      throw std::invalid_argument("Invalid local commit observation");
  }
  auto result = path == ReplyPath::Punctuation
                    ? session.punctuation(packet, epoch)
                    : session.key(packet, epoch);
  if (!session.input_enabled())
    path = result.reply_expected ? ReplyPath::IgnoredNavigation
                                 : ReplyPath::NoReply;
  return stage(result, path, uiless, std::move(local_text));
}
std::optional<PendingReply> ReplyComposer::basic_key(
    ServerSession &session, const FanyImeNamedpipeData &packet, uint64_t epoch,
    TsfPreeditStyle style, std::optional<std::string> local_text) {
  if (pending_ || packet.client_id != client_ || epoch != epoch_)
    throw std::logic_error("Pending or expired Windows reply route");
  if (style != TsfPreeditStyle::Local && style != TsfPreeditStyle::Pinyin &&
      style != TsfPreeditStyle::Empty)
    throw std::invalid_argument("Invalid TSF preedit style");
  const auto action = translate_key(packet);
  const bool uiless = (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0;
  if (action.kind == KeyKind::LocalReset)
    return dispatch(session, packet, epoch, ReplyPath::LocalCancel, uiless);
  if (action.kind == KeyKind::Ignore)
    return dispatch(session, packet, epoch, ReplyPath::NoReply, uiless);
  if (action.kind == KeyKind::CancelAndForward)
    return std::nullopt; // Configuration-specific shortcuts are not generic
                         // cancel.
  if (action.kind == KeyKind::Command && action.value == MSIME_COMMIT_RAW)
    return dispatch(session, packet, epoch, ReplyPath::LocalCommit, uiless,
                    std::move(local_text));
  if (auto edited = edit(session, packet, epoch, style))
    return edited;
  const auto view = session.view();
  const auto mode = view.at("local_mode").get<std::string>();
  if (mode == "unknown")
    return std::nullopt;
  const auto key = normalize_digit_key(packet.keycode);
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  const bool digit = key >= '1' && key <= '9';
  if ((key == 0x20 && modifiers == 0) ||
      (digit && modifiers == (mode == "unicode" ? 1u : 0u)))
    return dispatch(session, packet, epoch, ReplyPath::Selection, uiless);
  return std::nullopt;
}
std::optional<PendingReply>
ReplyComposer::edit(ServerSession &session, const FanyImeNamedpipeData &packet,
                    uint64_t epoch, TsfPreeditStyle style) {
  if (pending_ || packet.client_id != client_ || epoch != epoch_)
    throw std::logic_error("Pending or expired Windows reply route");
  if (style != TsfPreeditStyle::Local && style != TsfPreeditStyle::Pinyin &&
      style != TsfPreeditStyle::Empty)
    throw std::invalid_argument("Invalid TSF preedit style");
  const auto before = session.view();
  if (session_ && before.at("session").get<uint64_t>() != session_)
    throw std::logic_error("Reply changed host session");
  if (!session.input_enabled())
    return std::nullopt;
  const auto kind =
      edit_kind(packet, before.at("local_mode").get<std::string>(),
                !before.at("editing_text").get<std::string>().empty(),
                before.value("microsoft_shuangpin", false),
                before.at("editing_text").get<std::string>(),
                before.at("caret_position").get<size_t>());
  if (kind == EditKind::None)
    return std::nullopt;
  auto result = session.key(packet, epoch);
  const bool uiless = (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0;
  const bool erased_all =
      kind == EditKind::Erase && result.transition.at("view")
                                     .at("editing_text")
                                     .get<std::string>()
                                     .empty();
  const auto path = uiless || (style != TsfPreeditStyle::Local &&
                               kind != EditKind::Caret && !erased_all)
                        ? ReplyPath::Composition
                        : ReplyPath::NoReply;
  result.reply_expected = path != ReplyPath::NoReply;
  return stage(result, path, uiless);
}
std::optional<PendingReply>
ReplyComposer::navigate(ServerSession &session,
                        const FanyImeNamedpipeData &packet, uint64_t epoch,
                        const NavigationBindings &bindings) {
  if (pending_ || packet.client_id != client_ || epoch != epoch_)
    throw std::logic_error("Pending or expired Windows reply route");
  if (session_ && session.view().at("session").get<uint64_t>() != session_)
    throw std::logic_error("Reply changed host session");
  auto result = session.navigate(packet, epoch, bindings);
  if (!result)
    return std::nullopt;
  ReplyPath path;
  switch (result->direction) {
  case NavigationReply::Ignored:
    path = ReplyPath::IgnoredNavigation;
    break;
  case NavigationReply::PreviousCandidate:
    path = ReplyPath::PreviousCandidate;
    break;
  case NavigationReply::NextCandidate:
    path = ReplyPath::NextCandidate;
    break;
  case NavigationReply::PreviousPage:
    path = ReplyPath::PreviousPage;
    break;
  case NavigationReply::NextPage:
    path = ReplyPath::NextPage;
    break;
  default:
    throw std::logic_error("Invalid shared navigation result");
  }
  return stage(result->key, path,
               (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0);
}
void ReplyComposer::confirm_delivery(uint64_t client, uint64_t epoch,
                                     uint64_t request) {
  const auto &current = pending();
  if (current.ui_selection || client != client_ || epoch != epoch_ ||
      request != current.source.request_id)
    throw std::logic_error("Expired reply delivery acknowledgement");
  if (current.encoded && !*current.encoded)
    throw std::logic_error("Unencodable reply cannot be acknowledged");
  prefix_ = current.next_prefix;
  pending_.reset();
}
std::optional<PendingReply> ReplyComposer::select_candidate(ServerSession &session,
    uint64_t expected_session, uint64_t generation, size_t index) {
  if (pending_ || !session.input_enabled()) return std::nullopt;
  const auto view = session.view();
  if (!expected_session || view.at("session") != expected_session ||
      (session_ && session_ != expected_session) ||
      view.at("generation") != generation || !view.at("focused").get<bool>())
    return std::nullopt;
  bool found = false;
  for (const auto &candidate : view.at("candidates")) {
    const auto &id = candidate.at("id");
    if (id.at("session") == expected_session &&
        id.at("generation") == generation && id.at("index") == index)
      found = true;
  }
  if (!found)
    return std::nullopt;
  auto transition = session.select(epoch_, generation, index);
  const auto &commit = transition.at("commit");
  const auto delta =
      commit.is_null() ? std::string{} : commit.get<std::string>();
  const auto &next_view = transition.at("view");
  const auto raw = next_view.at("editing_text").get<std::string>();
  PendingReply next{
      {client_, epoch_, 0, true, std::move(transition)}, std::nullopt, prefix_};
  if (delta.empty())
    next.ui_selection = ui_rejected_selection();
  else if (raw.empty()) {
    next.ui_selection = ui_complete_selection(prefix_ + delta);
    next.next_prefix.clear();
  } else {
    next.next_prefix = prefix_ + delta;
    next.ui_selection = ui_partial_selection(
        raw, next.next_prefix,
        next.next_prefix +
            next.source.transition.at("view").at("preedit").get<std::string>());
  }
  if (!next.ui_selection)
    throw std::runtime_error(
        "Unencodable UI selection; disconnect without replay");
  session_ = expected_session;
  pending_ = std::move(next);
  return pending_;
}
void ReplyComposer::confirm_ui_delivery(uint64_t client, uint64_t epoch,
                                        uint64_t generation) {
  const auto &current = pending();
  if (!current.ui_selection || client != client_ || epoch != epoch_ ||
      current.source.transition.at("view").at("generation") != generation)
    throw std::logic_error("Expired UI delivery acknowledgement");
  prefix_ = current.next_prefix;
  pending_.reset();
}
void ReplyComposer::cancel() {
  pending_.reset();
  prefix_.clear();
}
std::optional<PendingReply> ReplyComposer::configured_key(
    ServerSession &session, const FanyImeNamedpipeData &packet, uint64_t epoch,
    TsfPreeditStyle style, const NavigationBindings &bindings,
    std::optional<std::string> local_text, WordCharacterBinding word_binding) {
  if (pending_ || packet.client_id != client_ || epoch != epoch_)
    throw std::logic_error("Pending or expired Windows reply route");
  if (style != TsfPreeditStyle::Local && style != TsfPreeditStyle::Pinyin &&
      style != TsfPreeditStyle::Empty)
    throw std::invalid_argument("Invalid TSF preedit style");
  if (auto word = session.word_character(packet, epoch, word_binding))
    return stage(word->key, word->exact
                                ? ReplyPath::Punctuation
                                : ReplyPath::CandidatePunctuationFallback);
  if (auto basic =
          basic_key(session, packet, epoch, style, std::move(local_text)))
    return basic;
  // basic_key checked pending/route/style and left unsupported keys untouched.
  const auto current = session.view();
  if (!session.input_enabled() || current.at("local_mode") == "unknown" ||
      current.at("editing_text").get<std::string>().empty())
    return std::nullopt;
  if (candidate_punctuation(packet, bindings))
    return dispatch(session, packet, epoch, ReplyPath::Punctuation,
                    (packet.modifiers_down & FanyImePipeFlags::UiLess) != 0);
  return navigate(session, packet, epoch, bindings);
}
} // namespace msime::windows

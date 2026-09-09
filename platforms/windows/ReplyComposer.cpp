#include "ReplyComposer.h"
#include <stdexcept>

namespace msime::windows {
namespace {
std::optional<NavigationReply> navigation_for(ReplyPath path) {
  switch (path) {
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
  auto result = session.key(packet, epoch);
  return stage(result, path, uiless, std::move(local_text));
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
  if (client != client_ || epoch != epoch_ ||
      request != current.source.request_id)
    throw std::logic_error("Expired reply delivery acknowledgement");
  if (current.encoded && !*current.encoded)
    throw std::logic_error("Unencodable reply cannot be acknowledged");
  prefix_ = current.next_prefix;
  pending_.reset();
}
void ReplyComposer::cancel() {
  pending_.reset();
  prefix_.clear();
}
} // namespace msime::windows

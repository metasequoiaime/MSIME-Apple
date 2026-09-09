#pragma once
#include "FocusGate.h"
#include "ReplyComposer.h"

namespace msime::windows {
struct PresentationCandidate {
  uint64_t session;
  uint64_t generation;
  size_t index;
  std::string text;
  bool highlighted;
};
struct CandidatePresentation {
  FocusLease lease;
  uint64_t session;
  uint64_t generation;
  bool visible = false;
  int x = 0;
  int y = 0;
  std::string preedit;
  std::vector<PresentationCandidate> candidates;
};
// Value-only projection. Call only from the confirmed-delivery callback.
// A future UI consumer must revalidate focus before displaying or clicking.
inline CandidatePresentation
candidate_presentation(const FocusLease &lease, const PendingReply &reply,
                       const FanyImeNamedpipeData &packet) {
  const auto &source = reply.source;
  if (!lease.epoch || source.client_id != lease.transport.client ||
      source.activation_epoch != lease.epoch ||
      packet.client_id != source.client_id ||
      packet.request_id != source.request_id ||
      packet.event_type != FanyImePipeEventType::KeyEvent)
    throw std::invalid_argument("Invalid candidate presentation identity");
  const auto &view = source.transition.at("view");
  CandidatePresentation output{lease,
                               view.at("session").get<uint64_t>(),
                               view.at("generation").get<uint64_t>(),
                               false,
                               packet.point[0],
                               packet.point[1],
                               {},
                               {}};
  if (!view.at("focused").get<bool>() ||
      (packet.modifiers_down & FanyImePipeFlags::UiLess) ||
      view.at("editing_text").get<std::string>().empty())
    return output;
  const auto text = view.at("preedit").get<std::string>();
  if (reply.next_prefix.size() > 4096 ||
      text.size() > 4096 - reply.next_prefix.size() ||
      view.at("candidates").size() > 9)
    throw std::invalid_argument("Oversized candidate presentation");
  output.preedit = reply.next_prefix + text;
  size_t highlighted = 0;
  for (const auto &candidate : view.at("candidates")) {
    const auto &id = candidate.at("id");
    PresentationCandidate item{
        id.at("session").get<uint64_t>(), id.at("generation").get<uint64_t>(),
        id.at("index").get<size_t>(), candidate.at("text").get<std::string>(),
        candidate.at("highlighted").get<bool>()};
    if (item.session != output.session ||
        item.generation != output.generation || item.text.size() > 4096)
      throw std::invalid_argument("Invalid presented candidate");
    highlighted += item.highlighted;
    output.candidates.push_back(std::move(item));
  }
  if (!output.candidates.empty() && highlighted != 1)
    throw std::invalid_argument("Invalid candidate highlight");
  output.visible = true;
  return output;
}
} // namespace msime::windows

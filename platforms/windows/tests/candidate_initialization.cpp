#include "../src/candidate/CandidatePresentation.h"
#include <cassert>

int main() {
  using namespace msime::windows;
  const FocusLease lease{{42, {1, 2, 3}}, 1, 1};
  PendingReply reply{};
  reply.source.client_id = 42;
  reply.source.activation_epoch = 1;
  reply.source.request_id = 7;
  reply.source.transition = {{"view", {
      {"session", 2}, {"generation", 3}, {"focused", true},
      {"editing_text", "synthetic"}, {"preedit", "synthetic"},
      {"candidates", nlohmann::json::array()}}}};
  FanyImeNamedpipeData packet{};
  packet.client_id = 42;
  packet.request_id = 7;
  packet.event_type = FanyImePipeEventType::KeyEvent;
  packet.point[0] = 12;
  packet.point[1] = 34;
  const auto visible = candidate_presentation(lease, reply, packet);
  assert(visible.visible && visible.preedit == "synthetic");
  assert(visible.session == 2 && visible.generation == 3);
  assert(visible.x == 12 && visible.y == 34);
  assert(visible.preedit_caret == std::string::npos);
  assert(visible.candidates.empty() && !visible.traditional_output);
  packet.modifiers_down = FanyImePipeFlags::UiLess;
  const auto hidden = candidate_presentation(lease, reply, packet);
  assert(!hidden.visible && hidden.preedit.empty());
  assert(hidden.preedit_caret == std::string::npos);
}

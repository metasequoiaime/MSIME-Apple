#include "CandidateMailbox.h"
#include <future>

using namespace msime::windows;
namespace {
void require(bool condition) {
  if (!condition)
    throw std::runtime_error("Candidate mailbox test failed");
}
} // namespace
void candidate_mailbox_tests() {
  FocusGate gate;
  CandidateMailbox mailbox;
  PipeTicket a{42, {1, 2, 3}}, b{43, {4, 5, 6}};
  auto activate = [&](const PipeTicket &ticket, uint64_t token) {
    const auto change = gate.begin(ticket, token);
    require(change.has_value());
    require(gate.acknowledge(change->pending, [] { return true; }));
    return change->pending;
  };
  auto publish = [&](const FocusLease &lease, uint64_t generation,
                     bool uiless = false) {
    FanyImeNamedpipeData packet{};
    packet.client_id = lease.transport.client;
    packet.request_id = generation;
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.modifiers_down = uiless ? FanyImePipeFlags::UiLess : 0;
    PendingReply reply{};
    reply.source.client_id = packet.client_id;
    reply.source.activation_epoch = lease.epoch;
    reply.source.request_id = packet.request_id;
    reply.source.transition = {{"view",
                                {{"session", 1},
                                 {"generation", generation},
                                 {"focused", true},
                                 {"editing_text", "U4"},
                                 {"preedit", "U4"},
                                 {"candidates", nlohmann::json::array()}}}};
    return gate.with_active(lease,
                            [&] { mailbox.delivered(lease, reply, packet); });
  };
  require(!mailbox.snapshot(gate));
  const auto first = activate(a, 1);
  require(publish(first, 1));
  require(mailbox.snapshot(gate)->visible);
  const auto pending = gate.begin(b, 2);
  require(pending.has_value() && !mailbox.snapshot(gate));
  require(gate.acknowledge(pending->pending, [] { return true; }));
  require(!mailbox.snapshot(gate)); // No old owner's frame on the new focus.
  require(!publish(first, 2));
  require(publish(pending->pending, 3));
  mailbox.disconnected(a);
  require(mailbox.snapshot(gate)->generation == 3);
  auto replacement = b;
  ++replacement.generations[0];
  const auto next = activate(replacement, 3);
  require(!mailbox.snapshot(gate));
  require(publish(next, 4, true));
  mailbox.disconnected(b);
  const auto hidden = mailbox.snapshot(gate);
  require(hidden && !hidden->visible && hidden->preedit.empty());
  auto reader = std::async(std::launch::async, [&] {
    for (size_t i = 0; i < 200; ++i) {
      const auto value = mailbox.snapshot(gate);
      require(value && same_ticket(value->lease.transport, replacement));
    }
  });
  for (uint64_t i = 5; i < 205; ++i)
    require(publish(next, i));
  reader.get();
  require(mailbox.snapshot(gate)->generation == 204);
  require(gate.deactivate(next));
  require(!mailbox.snapshot(gate));
  const auto final = activate(replacement, 4);
  require(publish(final, 205));
  mailbox.disconnected(replacement);
  require(!mailbox.snapshot(gate));
  require(publish(final, 206));
  mailbox.stop();
  require(publish(final, 207));
  require(
      !mailbox.snapshot(gate)); // A late delivery cannot reopen a stopped UI.
}

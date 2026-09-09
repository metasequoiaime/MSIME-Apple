#include "CandidateMailbox.h"
#include "CandidateClickWorker.h"
#include "CandidateLayout.h"
#include "ModeMailbox.h"
#include "ModeLayout.h"
#include <future>

using namespace msime::windows;
namespace {
class ModeTransport final : public MainTransport {
public:
  bool current(const PipeTicket &) override { return open; }
  bool try_current(const PipeTicket &) override { return open; }
  std::optional<FanyImeNamedpipeData>
  read(const PipeTicket &) override { return std::nullopt; }
  bool send(const PipeTicket &, uint32_t,
            const std::vector<uint8_t> &) override { return open; }
  void close(const PipeTicket &) noexcept override { open = false; }
  bool open = true;
};
void require(bool condition) {
  if (!condition)
    throw std::runtime_error("Candidate mailbox test failed");
}
} // namespace
void candidate_mailbox_tests() {
  for (unsigned dpi : {48u, 96u, 144u, 192u, 384u, 960u}) {
    for (int width : {2, 5, 100, 1920}) {
      const auto layout = mode_layout(-width, -7, 0, 0, dpi);
      require(layout && layout->x >= -width && layout->y >= -7 &&
              layout->x + layout->width() == 0 &&
              layout->y + layout->height() == 0);
      for (size_t i = 0; i < 6; ++i)
        require(layout->hit(static_cast<int>(i % 2) * layout->cell_width,
                            static_cast<int>(i / 2) * layout->cell_height) == i);
      require(!layout->hit(-1, 0) && !layout->hit(layout->width(), 0) &&
              !layout->hit(0, layout->height()));
    }
  }
  require(!mode_layout(0, 0, 1, 3, 96));
  require(!mode_layout(0, 0, 2, 2, 96));
  const auto extreme_mode = mode_layout(INT32_MIN, INT32_MIN, INT32_MAX,
                                        INT32_MAX, 960);
  require(extreme_mode && extreme_mode->x == INT32_MAX - 2240);
  {
    CandidateClick click{{{42, {1, 2, 3}}, 1, 1}, 2, 3, 4};
    std::promise<void> entered, release;
    auto started = entered.get_future();
    auto resume = release.get_future();
    size_t calls = 0;
    const auto caller = std::this_thread::get_id();
    CandidateClickWorker worker([&](const CandidateClick &value) {
      require(std::this_thread::get_id() != caller && value.index == 4);
      ++calls;
      entered.set_value();
      require(resume.wait_for(std::chrono::seconds(10)) ==
              std::future_status::ready);
    });
    require(worker.submit(click));
    require(started.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    const bool busy_rejected = !worker.submit(click);
    worker.request_stop();
    release.set_value();
    worker.stop();
    require(busy_rejected && calls == 1 && !worker.failed() &&
            !worker.submit(click));
    std::promise<void> failing;
    auto began = failing.get_future();
    CandidateClickWorker failed([&](const CandidateClick &) {
      failing.set_value();
      throw std::runtime_error("Synthetic click failure");
    });
    require(failed.submit(click));
    require(began.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    failed.stop();
    require(failed.failed() && !failed.submit(click));
  }
  for (unsigned dpi : {96u, 120u, 144u, 192u, 288u, 384u}) {
    const auto metrics = candidate_metrics(dpi);
    require(!candidate_hit(metrics.padding, metrics.padding, metrics.width,
                           1000, dpi, 9));
    for (size_t row = 0; row < 9; ++row)
      require(candidate_hit(metrics.padding,
                            metrics.padding +
                                static_cast<int>(row + 1) * metrics.row,
                            metrics.width, 2000, dpi, 9) == row);
    require(!candidate_hit(-1, 100, metrics.width, 1000, dpi, 9));
    require(!candidate_hit(metrics.width, 100, metrics.width, 1000, dpi, 9));
    require(!candidate_hit(metrics.padding, 10 * metrics.row + metrics.padding,
                           metrics.width, 2000, dpi, 9));
    require(metrics.row == static_cast<int>(28 * dpi / 96));
    require(metrics.font == static_cast<int>(16 * dpi / 96));
    for (size_t count = 0; count <= 9; ++count) {
      const auto bounds =
          candidate_bounds(-5000, 5000, -1920, -1080, 0, 0, dpi, count);
      require(bounds.x == -1920 && bounds.y + bounds.height == 0);
      require(bounds.width > 0 && bounds.width <= 1920);
      require(bounds.height > 0 && bounds.height <= 1080);
    }
  }
  const auto tiny =
      candidate_bounds(INT32_MAX, INT32_MIN, -3, -2, 2, 4, 960, 9);
  require(tiny.x == -3 && tiny.y == -2 && tiny.width == 5 && tiny.height == 6);
  const auto extreme = candidate_bounds(INT32_MAX, INT32_MIN, INT32_MIN,
                                        INT32_MIN, INT32_MAX, INT32_MAX, 96, 9);
  require(extreme.x == INT32_MAX - 420 && extreme.y == INT32_MIN);
  for (int invalid = 0; invalid < 4; ++invalid) {
    bool rejected = false;
    try {
      (void)candidate_bounds(0, 0, 0, 0, invalid == 2 ? 0 : 100, 100,
                             invalid == 0   ? 0
                             : invalid == 1 ? 961
                                            : 96,
                             invalid == 3 ? 10 : 9);
    } catch (const std::invalid_argument &) {
      rejected = true;
    }
    require(rejected);
  }
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
  {
    ModeMailbox modes;
    ModeTransport transport;
    require(!modes.snapshot(gate, transport));
    const auto lease = activate(a, 9);
    FanyImeNamedpipeData packet{};
    packet.client_id = a.client;
    packet.event_type = FanyImePipeEventType::StatusSnapshot;
    packet.keycode = 1;
    packet.modifiers_down = 1;
    packet.pinyin_length = 1;
    gate.with_active(lease, [&] { modes.event(lease, packet); });
    auto value = modes.snapshot(gate, transport);
    require(value && value->chinese == true && value->fullwidth == true &&
            value->chinese_punctuation == true);
    modes.disconnected(a);
    require(!modes.snapshot(gate, transport));
    auto replacement = a;
    ++replacement.generations[0];
    const auto next = activate(replacement, 10);
    packet.event_type = FanyImePipeEventType::ClientActivated;
    gate.with_active(next, [&] { modes.event(next, packet); });
    modes.disconnected(a); // Late old-stream cleanup cannot erase replacement.
    value = modes.snapshot(gate, transport);
    require(value && same_ticket(value->lease.transport, replacement) &&
            !value->chinese && !value->chinese_punctuation && !value->fullwidth);
    transport.open = false;
    require(!modes.snapshot(gate, transport));
    transport.open = true;
    require(modes.snapshot(gate, transport).has_value());
    modes.stop();
    packet.event_type = FanyImePipeEventType::StatusSnapshot;
    gate.with_active(next, [&] { modes.event(next, packet); });
    require(!modes.snapshot(gate, transport));
  }
  require(!mailbox.snapshot(gate));
  const auto first = activate(a, 1);
  require(publish(first, 1));
  require(mailbox.snapshot(gate)->visible);
  {
    std::promise<void> held, release;
    auto holding = held.get_future();
    auto resume = release.get_future();
    auto writer = std::async(std::launch::async, [&] {
      return gate.with_active(first, [&] {
        held.set_value();
        require(resume.wait_for(std::chrono::seconds(10)) ==
                std::future_status::ready);
      });
    });
    require(holding.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    auto reader = std::async(std::launch::async,
                             [&] { return mailbox.snapshot(gate, false); });
    const bool ready =
        reader.wait_for(std::chrono::seconds(1)) == std::future_status::ready;
    release.set_value();
    require(writer.get());
    const auto blocked = reader.get();
    require(ready && !blocked);
    require(mailbox.snapshot(gate, false)->visible);
    require(!mailbox.snapshot(gate, false,
                              [](const FocusLease &) { return false; }));
  }
  auto visual_event = [&](const FocusLease &lease, uint32_t type,
                          uint32_t modifiers = 0, uint32_t keycode = 0) {
    FanyImeNamedpipeData packet{};
    packet.client_id = lease.transport.client;
    packet.event_type = type;
    packet.modifiers_down = modifiers;
    packet.keycode = keycode;
    packet.point[0] = -200;
    packet.point[1] = 300;
    return gate.with_active(lease, [&] { mailbox.event(lease, packet); });
  };
  require(visual_event(first, FanyImePipeEventType::HideCandidateWnd));
  const auto suppressed = mailbox.snapshot(gate);
  require(suppressed && !suppressed->visible && suppressed->preedit.empty() &&
          suppressed->candidates.empty());
  require(visual_event(first, FanyImePipeEventType::MoveCandidateWnd));
  require(!mailbox.snapshot(gate)->visible &&
          mailbox.snapshot(gate)->x == -200);
  require(visual_event(first, FanyImePipeEventType::ShowCandidateWnd));
  require(!mailbox.snapshot(gate)->visible &&
          mailbox.snapshot(gate)->generation == 1);
  require(visual_event(first, FanyImePipeEventType::HideCandidateWnd));
  require(publish(first, 2));
  require(mailbox.snapshot(gate)->visible); // A new confirmed key refreshes UI.
  require(visual_event(first, FanyImePipeEventType::MoveCandidateWnd,
                       FanyImePipeFlags::UiLess));
  const auto host_drawn = mailbox.snapshot(gate);
  require(host_drawn && !host_drawn->visible && host_drawn->preedit.empty() &&
          host_drawn->candidates.empty() && host_drawn->x == -200);
  require(visual_event(first, FanyImePipeEventType::MoveCandidateWnd));
  require(!mailbox.snapshot(gate)->visible);
  require(visual_event(first, FanyImePipeEventType::ShowCandidateWnd));
  require(mailbox.snapshot(gate)->visible &&
          mailbox.snapshot(gate)->generation == 2);
  require(visual_event(first, FanyImePipeEventType::ShowCandidateWnd, FanyImePipeFlags::UiLess));
  require(!mailbox.snapshot(gate)->visible);
  for (auto mode_event : {FanyImePipeEventType::IMESwitch,
                          FanyImePipeEventType::StatusSnapshot,
                          FanyImePipeEventType::FocusRestored}) {
    require(publish(first, 2));
    require(visual_event(first, mode_event, 0, 1));
    require(mailbox.snapshot(gate)->visible);
    require(visual_event(first, FanyImePipeEventType::PuncSwitch));
    require(mailbox.snapshot(gate)->visible);
    auto stale = first;
    ++stale.token;
    require(!visual_event(stale, mode_event));
    require(mailbox.snapshot(gate)->visible);
    require(visual_event(first, mode_event));
    require(!mailbox.snapshot(gate)->visible &&
            mailbox.snapshot(gate)->candidates.empty());
    require(visual_event(first, mode_event, 0, 1));
    require(visual_event(first, FanyImePipeEventType::ShowCandidateWnd));
    require(!mailbox.snapshot(gate)->visible);
  }
  const auto pending = gate.begin(b, 2);
  require(pending.has_value() && !mailbox.snapshot(gate));
  require(gate.acknowledge(pending->pending, [] { return true; }));
  require(!mailbox.snapshot(gate)); // No old owner's frame on the new focus.
  require(!publish(first, 2));
  require(publish(pending->pending, 3));
  require(!visual_event(first, FanyImePipeEventType::HideCandidateWnd));
  require(mailbox.snapshot(gate)->visible);
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
  require(visual_event(next, FanyImePipeEventType::ShowCandidateWnd));
  require(!mailbox.snapshot(gate)->visible);
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

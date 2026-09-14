#include "../VoiceControllerMailbox.h"
#include <cassert>
#include <stdexcept>
#include <thread>

int main() {
  using namespace msime::windows;
  using namespace FanyImeVoiceController;
  auto owner = std::make_shared<VoiceControllerChannel>();
  auto stranger = std::make_shared<VoiceControllerChannel>();
  FocusLease lease{{77, {1, 2, 3}}, 4, 5};
  bool valid = true, change_during_start = false,
       disconnect_during_start = false;
  bool available = true, throws = false;
  int starts = 0, stops = 0, cancels = 0;
  std::shared_ptr<VoiceReviewResult> result;
  VoiceControllerDispatch dispatcher(
      {[&]() -> std::optional<FocusLease> { return lease; },
       [&](const FocusLease &captured) {
         return valid && captured.epoch == lease.epoch;
       },
       [&](std::string_view language) {
         assert(language == "en-US");
         ++starts;
         if (throws)
           throw std::runtime_error("synthetic failure");
         if (!available)
           return std::shared_ptr<VoiceReviewResult>{};
         result = std::make_shared<VoiceReviewResult>();
         if (change_during_start)
           ++lease.epoch;
         if (disconnect_during_start)
           owner->alive.store(false);
         return result;
       },
       [&](const auto &expected) {
         assert(expected == result);
         ++stops;
         expected->recognizing();
         return true;
       },
       [&](const auto &expected) {
         ++cancels;
         expected->cancel();
         return true;
       }});
  uint64_t request_id = 0;
  auto request = [&](Operation operation, uint64_t session = 0) {
    VoiceControllerRequest value;
    value.header.operation = operation;
    value.header.request_id = ++request_id;
    value.header.controller_id = (uint64_t{1} << 32) | 1;
    value.header.session_id = session;
    if (operation == Operation::Start) {
      value.language = "en-US";
      value.header.language_bytes =
          static_cast<uint32_t>(value.language.size());
    }
    return value;
  };
  auto check = [](const VoiceControllerResponse &response) {
    assert(valid_reply(response.header, sizeof(Reply) + response.text.size()));
  };
  auto started = dispatcher.dispatch(owner, request(Operation::Start));
  check(started);
  const auto first = started.header.session_id;
  assert(first && started.header.phase == Phase::Recording && starts == 1);
  assert(
      dispatcher.dispatch(stranger, request(Operation::Start)).header.status ==
      Status::Busy);
  assert(dispatcher.dispatch(stranger, request(Operation::Stop, first))
             .header.status == Status::Stale);
  assert(dispatcher.dispatch(owner, request(Operation::Stop, first + 1))
             .header.status == Status::Stale);
  assert(stops == 0 && cancels == 0);
  result->level(0.5f);
  auto polled = dispatcher.dispatch(owner, request(Operation::Poll, first));
  check(polled);
  assert(polled.header.level == 500 && polled.text.empty());
  auto stopped = dispatcher.dispatch(owner, request(Operation::Stop, first));
  check(stopped);
  assert(stopped.header.phase == Phase::Recognizing && stops == 1);
  result->processing();
  result->complete("synthetic transcript");
  auto completed = dispatcher.dispatch(owner, request(Operation::Poll, first));
  check(completed);
  assert(completed.header.phase == Phase::Complete &&
         completed.text == "synthetic transcript");
  valid = false;
  auto stale = dispatcher.dispatch(owner, request(Operation::Poll, first));
  check(stale);
  assert(stale.header.status == Status::Stale && stale.text.empty());
  assert(result->snapshot().phase == Phase::Cancelled && cancels == 1);
  valid = true;
  auto next = dispatcher.dispatch(owner, request(Operation::Start));
  assert(next.header.session_id > first);
  auto old = result;
  owner->alive.store(false);
  dispatcher.maintain();
  assert(old->snapshot().phase == Phase::Cancelled);
  assert(dispatcher.dispatch(owner, request(Operation::Start)).header.status ==
         Status::Stale);
  owner = std::make_shared<VoiceControllerChannel>();
  auto reconnected = dispatcher.dispatch(owner, request(Operation::Start));
  assert(reconnected.header.session_id > next.header.session_id);
  assert(dispatcher.dispatch(owner, request(Operation::Poll, first))
             .header.status == Status::Stale);
  old->complete("synthetic late completion");
  assert(result->snapshot().phase == Phase::Recording);
  auto cancelled = dispatcher.dispatch(
      owner, request(Operation::Cancel, reconnected.header.session_id));
  check(cancelled);
  assert(cancelled.header.phase == Phase::Cancelled && cancelled.text.empty());
  dispatcher.retire();
  change_during_start = true;
  assert(dispatcher.dispatch(owner, request(Operation::Start)).header.status ==
         Status::Stale);
  assert(result->snapshot().phase == Phase::Cancelled);
  change_during_start = false;
  disconnect_during_start = true;
  assert(dispatcher.dispatch(owner, request(Operation::Start)).header.status ==
         Status::Stale);
  assert(result->snapshot().phase == Phase::Cancelled);
  disconnect_during_start = false;
  owner = std::make_shared<VoiceControllerChannel>();
  available = false;
  assert(dispatcher.dispatch(owner, request(Operation::Start)).header.status ==
         Status::Unavailable);
  available = true;
  throws = true;
  auto failed = dispatcher.dispatch(owner, request(Operation::Start));
  check(failed);
  assert(failed.header.status == Status::Unavailable);
  throws = false;

  VoiceControllerMailbox mailbox;
  auto job = std::make_shared<VoiceControllerJob>();
  job->channel = owner;
  job->request = request(Operation::Start);
  assert(mailbox.publish(job));
  assert(!mailbox.publish(job));
  owner->alive.store(false); // timed-out queued Start is never executed
  auto queued = mailbox.take();
  const auto before = starts;
  auto ignored = dispatcher.dispatch(queued->channel, queued->request);
  assert(ignored.header.status == Status::Stale && starts == before);
  queued->complete(ignored);
  assert(!queued->wait(std::chrono::milliseconds(0)));
  auto fresh = std::make_shared<VoiceControllerJob>();
  fresh->channel = std::make_shared<VoiceControllerChannel>();
  fresh->request = request(Operation::Start);
  assert(mailbox.publish(fresh));
  assert(mailbox.take() == fresh);
  std::thread responder([&] {
    VoiceControllerResponse response;
    response.header.request_id = 42;
    fresh->complete(response);
  });
  auto response = fresh->wait(std::chrono::seconds(1));
  responder.join();
  assert(response && response->header.request_id == 42);
}

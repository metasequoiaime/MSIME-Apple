#include "../../src/voice/VoiceReviewResult.h"
#include <cassert>
#include <limits>
#include <thread>

int main() {
  using namespace msime::windows;
  using Phase = VoiceReviewResult::Phase;
  auto review = std::make_shared<VoiceReviewResult>();
  assert(review->active() && review->snapshot().phase == Phase::Recording);
  review->level(2.0f);
  assert(review->snapshot().level == 1000);
  review->level(-1.0f);
  assert(review->snapshot().level == 0);
  review->level(std::numeric_limits<float>::quiet_NaN());
  assert(review->snapshot().level == 0);
  review->level(std::numeric_limits<float>::infinity());
  assert(review->snapshot().level == 0);
  review->level(0.5f);
  assert(review->snapshot().level == 500);
  review->complete("synthetic premature result");
  assert(review->snapshot().phase == Phase::Recording);
  review->processing();
  assert(review->snapshot().phase == Phase::Recording);
  review->recognizing();
  review->level(1.0f);
  assert(review->snapshot().phase == Phase::Recognizing &&
         review->snapshot().level == 0);
  review->processing();
  review->recognizing();
  assert(review->snapshot().phase == Phase::Processing);
  int native_commits = 0;
  for (const auto mode : {"tsf", "sendinput", "ctrl_v", "unknown"}) {
    assert(!voice_inline_allowed(review, true, true, mode));
    deliver_voice_result(review, "synthetic reviewed result",
                         [&] { ++native_commits; });
    assert(native_commits == 0);
  }
  assert(review->snapshot().phase == Phase::Complete && !review->active());
  assert(review->snapshot().text == "synthetic reviewed result");
  review->fail();
  review->complete("synthetic late overwrite");
  review->processing();
  assert(review->snapshot().text == "synthetic reviewed result");
  review->cancel();
  deliver_voice_result(review, "synthetic late result",
                       [&] { ++native_commits; });
  assert(review->snapshot().phase == Phase::Cancelled &&
         review->snapshot().text.empty());
  assert(native_commits == 0);
  assert(voice_inline_allowed({}, true, true, "tsf"));
  assert(!voice_inline_allowed({}, false, true, "tsf"));
  assert(!voice_inline_allowed({}, true, false, "tsf"));
  assert(!voice_inline_allowed({}, true, true, "ctrl_v"));
  deliver_voice_result({}, "synthetic native result",
                       [&] { ++native_commits; });
  assert(native_commits == 1);

  for (const auto &invalid :
       {std::string{}, std::string("\xc0\xaf", 2), std::string("a\0b", 3),
        std::string(FanyImeVoiceController::MaxTextBytes + 1, 'x')}) {
    auto result = std::make_shared<VoiceReviewResult>();
    result->recognizing();
    deliver_voice_result(result, invalid, [&] { ++native_commits; });
    assert(result->snapshot().phase == Phase::Failed);
    assert(result->snapshot().text.empty() && !result->active());
    result->complete("synthetic late result");
    assert(result->snapshot().phase == Phase::Failed);
  }
  assert(native_commits == 1); // invalid review text must not trigger fallback
  auto maximum = std::make_shared<VoiceReviewResult>();
  maximum->recognizing();
  maximum->complete(std::string(FanyImeVoiceController::MaxTextBytes, 'x'));
  assert(maximum->snapshot().phase == Phase::Complete);

  for (int i = 0; i < 100; ++i) {
    auto old = std::make_shared<VoiceReviewResult>();
    auto next = std::make_shared<VoiceReviewResult>();
    old->recognizing();
    std::thread worker([&] {
      old->processing();
      old->complete("synthetic racing result");
    });
    std::thread polling([&] {
      for (int n = 0; n < 10; ++n) {
        const auto snapshot = old->snapshot();
        assert(snapshot.level == 0);
        assert(snapshot.phase == Phase::Complete || snapshot.text.empty());
      }
    });
    old->cancel();
    worker.join();
    polling.join();
    assert(old->snapshot().phase == Phase::Cancelled &&
           old->snapshot().text.empty());
    assert(next->snapshot().phase == Phase::Recording &&
           next->snapshot().text.empty());
  }
}

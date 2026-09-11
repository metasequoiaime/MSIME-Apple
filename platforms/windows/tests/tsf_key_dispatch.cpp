#include "TsfKeyDispatch.h"

#include <cstdlib>

using namespace msime::windows;

int main() {
  const auto sent = decide_tsf_key_dispatch(KeyEventSendResult::Sent, true, true);
  if (sent.result != TsfKeyDispatchResult::Complete || !sent.eaten || sent.deferred_replay)
    return EXIT_FAILURE;
  const auto retry = decide_tsf_key_dispatch(KeyEventSendResult::DeliveryAmbiguous, false, false);
  if (retry.result != TsfKeyDispatchResult::Retry || !retry.eaten)
    return EXIT_FAILURE;
  const auto deferred = decide_tsf_key_dispatch(KeyEventSendResult::DefinitelyNotSent, true, true);
  if (deferred.result != TsfKeyDispatchResult::AwaitingCompletion || !deferred.deferred_replay)
    return EXIT_FAILURE;
  const auto released = decide_tsf_key_dispatch(KeyEventSendResult::DeliveryAmbiguous, true, false);
  if (released.result != TsfKeyDispatchResult::Complete || released.eaten)
    return EXIT_FAILURE;
  return EXIT_SUCCESS;
}

#include "KeyEventSendResult.h"

#include <cstdlib>

using msime::windows::KeyEventSendResult;
using msime::windows::definitely_not_sent;

int main() {
  if (!definitely_not_sent(KeyEventSendResult::DefinitelyNotSent))
    return EXIT_FAILURE;
  if (definitely_not_sent(KeyEventSendResult::Sent) ||
      definitely_not_sent(KeyEventSendResult::DeliveryAmbiguous))
    return EXIT_FAILURE;
  return EXIT_SUCCESS;
}

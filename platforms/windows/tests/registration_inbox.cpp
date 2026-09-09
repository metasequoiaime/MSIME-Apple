#include "RegistrationInbox.h"
#include <future>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Registration inbox test failed");
}
int main() {
  RegistrationInbox inbox(1);
  PipeTicket a{42, {1, 2, 3}}, b{43, {4, 5, 6}};
  require(!inbox.push({0, {1, 2, 3}}) && !inbox.push({42, {1, 0, 3}}));
  require(inbox.push(a) && !inbox.push(b));
  auto first = inbox.take_for(std::chrono::milliseconds(1));
  require(first && same_ticket(*first, a));
  require(!inbox.take_for(std::chrono::milliseconds(1)));
  auto waiting = std::async(std::launch::async, [&] {
    return inbox.take_for(std::chrono::seconds(2));
  });
  require(inbox.push(b));
  auto second = waiting.get();
  require(second && same_ticket(*second, b));
  require(inbox.push(a));
  inbox.close();
  require(inbox.closed() && !inbox.push(b) &&
          !inbox.take_for(std::chrono::seconds(2)));
}

#include "ClipboardPresentation.h"
#include <cassert>
int main() {
  msime::windows::ClipboardMailbox mailbox;
  assert(!mailbox.snapshot());
  mailbox.publish(true, {"alpha", "beta"});
  auto first = mailbox.snapshot();
  assert(first && first->enabled && first->revision == 1 && first->items.size() == 2);
  mailbox.publish(true, {"alpha", "beta"});
  assert(mailbox.snapshot()->revision == 1);
  mailbox.publish(false, {});
  auto second = mailbox.snapshot();
  assert(second && !second->enabled && second->revision == 2 && second->items.empty());
  mailbox.clear();
  assert(!mailbox.snapshot());
}

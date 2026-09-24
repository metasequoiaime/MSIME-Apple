#include "../src/candidates/CandidateActionPolicy.h"

#include <cassert>
#include <string>

int main() {
  using msime::linux_host::candidate_dictionary_removal_available;
  using msime::linux_host::candidate_removal_available;
  using msime::linux_host::candidate_removal_slot;
  assert(!candidate_removal_available(""));
  assert(!candidate_removal_available("a"));
  assert(!candidate_removal_available("字"));
  assert(!candidate_removal_available("😀"));
  assert(candidate_removal_available("ab"));
  assert(candidate_removal_available("词语"));
  assert(candidate_removal_available("😀a"));
  assert(!candidate_removal_available("\xc0\x80"));
  assert(!candidate_removal_available("\xed\xa0\x80"));
  assert(!candidate_removal_available("ab\xff"));
  assert(!candidate_removal_available("词\xe4\xb"));
  assert(candidate_dictionary_removal_available(0, 0, "词语"));
  assert(candidate_dictionary_removal_available(0, 1, "词语"));
  assert(candidate_dictionary_removal_available(0, 4, "词语"));
  assert(candidate_dictionary_removal_available(0, 4, "a"));
  assert(!candidate_dictionary_removal_available(0, 0, "词"));
  assert(!candidate_dictionary_removal_available(0, 4, "a\xff"));
  assert(!candidate_dictionary_removal_available(3, 0, "词语"));
  assert(!candidate_dictionary_removal_available(0, 2, "词语"));
  assert(candidate_removal_slot('1', 0) == 0);
  assert(candidate_removal_slot('8', 0) == 7);
  assert(candidate_removal_slot('&', 2) == 0);
  assert(candidate_removal_slot('x', 9) == 7);
  assert(!candidate_removal_slot('&', 0));
  // Same wording as the Windows candidate menu (置顶, 第 N 位).
  assert(std::string(msime::linux_host::candidate_pin_label) == "置顶");
  assert(msime::linux_host::candidate_fix_label(1) == "固定到第 1 位");
  assert(msime::linux_host::candidate_fix_label(5) == "固定到第 5 位");
}

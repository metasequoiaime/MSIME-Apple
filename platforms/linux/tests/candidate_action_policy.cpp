#include "CandidateActionPolicy.h"

#include <cassert>

int main() {
  using msime::linux_host::candidate_removal_available;
  assert(!candidate_removal_available(""));
  assert(!candidate_removal_available("a"));
  assert(!candidate_removal_available("字"));
  assert(!candidate_removal_available("😀"));
  assert(candidate_removal_available("ab"));
  assert(candidate_removal_available("词语"));
  assert(candidate_removal_available("😀a"));
  assert(!candidate_removal_available("\xc0\x80"));
  assert(!candidate_removal_available("\xed\xa0\x80"));
}

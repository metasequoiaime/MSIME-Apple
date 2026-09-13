#include "CandidatePalette.h"

#include <cassert>

int main() {
  using msime::linux_host::candidate_builtin_accent;
  assert(candidate_builtin_accent("fluent", false) == 0x6B69D6u);
  assert(candidate_builtin_accent("fluent", true) == 0x6B69D6u);
  assert(candidate_builtin_accent("wechat", false) == 0x07C160u);
  assert(candidate_builtin_accent("graphite", false) == 0x5F6B7Au);
  assert(candidate_builtin_accent("graphite", true) == 0x8993A0u);
  assert(candidate_builtin_accent("willow_green", false) == 0x58B980u);
  assert(candidate_builtin_accent("willow_green", true) == 0x65C98Du);
  assert(candidate_builtin_accent("unknown", false) == 0x6B69D6u);
}

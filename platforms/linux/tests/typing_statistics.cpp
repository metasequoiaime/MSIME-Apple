#include "../TypingStatistics.h"

#include <cassert>
#include <string_view>

using msime::linux_host::resolve_typing_source;
using msime::linux_host::typing_source_id;
using msime::linux_host::TypingSource;

int main() {
  assert(resolve_typing_source(0, false, false, "none", "xiaohe") ==
         TypingSource::Quanpin);
  assert(resolve_typing_source(0, true, false, "none", "xiaohe") ==
         TypingSource::NineKey);
  assert(resolve_typing_source(1, false, false, "none", "xiaohe") ==
         TypingSource::Shuangpin);
  assert(resolve_typing_source(1, false, false, "none", "ziranma") ==
         TypingSource::Ziranma);
  assert(resolve_typing_source(1, false, false, "none", "microsoft") ==
         TypingSource::Microsoft);
  assert(resolve_typing_source(1, false, false, "none", "shoudao") ==
         TypingSource::Shoudao);
  assert(resolve_typing_source(2, false, false, "none", "xiaohe") ==
         TypingSource::Wubi);
  assert(resolve_typing_source(3, false, false, "none", "xiaohe") ==
         TypingSource::Japanese);
  assert(resolve_typing_source(0, false, true, "none", "xiaohe") ==
         TypingSource::English);
  assert(resolve_typing_source(0, false, false, "temporary_japanese",
                               "xiaohe") == TypingSource::Japanese);
  assert(resolve_typing_source(0, false, false, "emoji", "xiaohe") ==
         TypingSource::Local);
  assert(resolve_typing_source(99, false, false, "none", "xiaohe") ==
         TypingSource::Unknown);
  assert(typing_source_id(TypingSource::NineKey) ==
         std::string_view("nineKey"));
  assert(typing_source_id(TypingSource::Voice) == std::string_view("voice"));
  return 0;
}

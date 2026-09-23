#include "../src/system/TypingStatistics.h"

#include <cassert>
#include <string_view>

using msime::linux_host::PassthroughModifiers;
using msime::linux_host::resolve_typing_source;
using msime::linux_host::should_count_passthrough_character;
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

  // Passthrough keys count as typed text only when they are printable and no shortcut modifier is held; Shift picks a character and does not make a shortcut.
  assert(should_count_passthrough_character(U'a', {}));
  assert(should_count_passthrough_character(U' ', {}));
  assert(should_count_passthrough_character(U'~', {}));
  assert(should_count_passthrough_character(U'\u00e9', {}));
  assert(should_count_passthrough_character(U'\U0001F600', {}));
  assert(!should_count_passthrough_character(U'\t', {}));
  assert(!should_count_passthrough_character(U'\r', {}));
  assert(!should_count_passthrough_character(0x1b, {}));
  assert(!should_count_passthrough_character(0x7f, {}));
  assert(!should_count_passthrough_character(0, {}));
  assert(!should_count_passthrough_character(0xd800, {}));
  assert(!should_count_passthrough_character(0x110000, {}));
  PassthroughModifiers control;
  control.control = true;
  assert(!should_count_passthrough_character(U'c', control));
  PassthroughModifiers alt;
  alt.alt = true;
  assert(!should_count_passthrough_character(U'f', alt));
  PassthroughModifiers super;
  super.super = true;
  assert(!should_count_passthrough_character(U'l', super));
  PassthroughModifiers hyper;
  hyper.hyper = true;
  assert(!should_count_passthrough_character(U'h', hyper));
  PassthroughModifiers meta;
  meta.meta = true;
  assert(!should_count_passthrough_character(U'm', meta));
  return 0;
}

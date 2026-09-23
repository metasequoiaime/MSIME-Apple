#include "../src/system/ChineseTextConversion.h"

#include <cassert>
#include <string>

int main() {
  // Phrase-level OpenCC s2t, the same pairs crates/client-core/src/chinese_conversion.rs pins. Character-by-character conversion (the former ICU Simplified-Traditional transliterator) gets the one-to-many characters wrong, e.g. 头发 -> 頭發.
  assert(msime_linux_simplified_to_traditional("头发") == "頭髮");
  assert(msime_linux_simplified_to_traditional("发展") == "發展");
  assert(msime_linux_simplified_to_traditional("干面") == "乾麪");
  assert(msime_linux_simplified_to_traditional("皇后") == "皇后");
  assert(msime_linux_simplified_to_traditional("后天") == "後天");
  assert(msime_linux_simplified_to_traditional("里面") == "裏面");
  assert(msime_linux_simplified_to_traditional("汉语输入法") == "漢語輸入法");
  // Text without a Traditional form is unchanged.
  assert(msime_linux_simplified_to_traditional("").empty());
  assert(msime_linux_simplified_to_traditional("hello 😀") == "hello 😀");
  assert(msime_linux_simplified_to_traditional("かな") == "かな");
  assert(msime_linux_simplified_to_traditional("漢語") == "漢語");
  // The host API rejects invalid UTF-8 and embedded NULs; the caller keeps its own text.
  const std::string invalid("\xff\xfe");
  assert(msime_linux_simplified_to_traditional(invalid) == invalid);
  const std::string embedded_nul("汉\0语", 7);
  assert(msime_linux_simplified_to_traditional(embedded_nul) == embedded_nul);
  return 0;
}

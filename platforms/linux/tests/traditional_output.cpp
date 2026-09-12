#include "../ChineseTextConversion.h"

#include <cassert>

int main() {
  assert(msime_linux_simplified_to_traditional("汉语输入法") == "漢語輸入法");
  assert(msime_linux_simplified_to_traditional("hello 😀") == "hello 😀");
  return 0;
}

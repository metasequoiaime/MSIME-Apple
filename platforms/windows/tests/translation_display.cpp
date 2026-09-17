#include "../TranslationDisplay.h"
#include <cassert>

using msime::windows::append_translation_display;

int main() {
  const auto joined = append_translation_display("synthetic primary", "合成次译");
  assert(joined == "synthetic primary / 合成次译");
  for (unsigned char ch : joined)
    assert(ch >= 32 && ch != 127);
  assert(append_translation_display("", "合成次译") == "合成次译");
  assert(append_translation_display("synthetic primary", "") == "synthetic primary");
  assert(append_translation_display("", "").empty());
  const std::string primary(4090, 'a');
  assert(append_translation_display(primary, "中").size() == 4096);
  assert(append_translation_display(primary, "中文") == primary);
  assert(append_translation_display(std::string(4096, 'a'), "b").size() == 4096);
  assert(append_translation_display("", std::string(4096, 'b')).size() == 4096);
  assert(append_translation_display("first", std::string(4097, 'b')) == "first");
  assert(append_translation_display(std::string(4097, 'a'), "b").empty());
}

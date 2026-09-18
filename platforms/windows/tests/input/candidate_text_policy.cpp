#include "input/CandidateTextPolicy.h"
#include <cassert>
#include <string>

int main() {
  using msime::windows::HanCharacterEdge;
  using msime::windows::extract_han_character;
  assert(extract_han_character("abc", HanCharacterEdge::First) == std::nullopt);
  assert(extract_han_character("a中b", HanCharacterEdge::First) == "中");
  assert(extract_han_character("a中b文", HanCharacterEdge::Last) == "文");
  assert(extract_han_character("𠀀a", HanCharacterEdge::First) == "𠀀");
  assert(extract_han_character("", HanCharacterEdge::Last) == std::nullopt);
  const std::string invalid("中\x80", 4);
  assert(extract_han_character(invalid, HanCharacterEdge::Last) == std::nullopt);
}

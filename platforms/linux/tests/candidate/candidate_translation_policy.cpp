#include "../src/candidates/CandidateTranslationPolicy.h"

#include <cassert>

int main() {
  using msime::linux_host::split_translation_gloss;
  assert((split_translation_gloss("apple; fruit") ==
          std::vector<std::string>{"apple", "fruit"}));
  assert((split_translation_gloss("苹果；家伙") ==
          std::vector<std::string>{"苹果", "家伙"}));
  assert((split_translation_gloss(" first ; ; second ; ") ==
          std::vector<std::string>{"first", "second"}));
  assert((split_translation_gloss("cloud gloss") ==
          std::vector<std::string>{"cloud gloss"}));
  assert(split_translation_gloss(" ; \xEF\xBC\x9B").empty());
}

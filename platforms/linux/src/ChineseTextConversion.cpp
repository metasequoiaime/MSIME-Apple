#include "ChineseTextConversion.h"

#include <memory>
#include <unicode/translit.h>
#include <unicode/unistr.h>

std::string msime_linux_simplified_to_traditional(const std::string &text) {
  if (text.empty())
    return text;
  UErrorCode status = U_ZERO_ERROR;
  std::unique_ptr<icu::Transliterator> converter(
      icu::Transliterator::createInstance("Simplified-Traditional",
                                          UTRANS_FORWARD, status));
  if (U_FAILURE(status) || !converter)
    return text;
  auto value = icu::UnicodeString::fromUTF8(text);
  converter->transliterate(value);
  std::string converted;
  value.toUTF8String(converted);
  return converted;
}

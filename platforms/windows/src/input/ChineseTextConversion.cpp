#include "ChineseTextConversion.h"

#include "msime_client.h"

namespace msime::windows {

std::string simplified_to_traditional(std::string_view text,
                                      bool traditional_output) {
  if (!traditional_output || text.empty())
    return std::string(text);
  // The shared OpenCC s2t tables, the same phrase-level conversion the reference server ships. A
  // character table cannot tell 头发 (頭髮) from 发展 (發展); LCMapStringEx was one.
  char *converted = msime_client_simplified_to_traditional(
      reinterpret_cast<const uint8_t *>(text.data()), text.size());
  if (!converted)
    return std::string(text);
  std::string result(converted);
  msime_client_string_free(converted);
  return result;
}

} // namespace msime::windows

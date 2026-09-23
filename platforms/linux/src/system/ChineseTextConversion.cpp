#include "ChineseTextConversion.h"

#include "msime_client.h"

#include <cstdint>
#include <memory>

std::string msime_linux_simplified_to_traditional(const std::string &text) {
  if (text.empty())
    return text;
  // The shared OpenCC s2t tables, the same conversion Windows uses; NULL means invalid UTF-8 or an embedded NUL, where the original text is kept.
  std::unique_ptr<char, void (*)(char *)> converted(
      msime_client_simplified_to_traditional(reinterpret_cast<const uint8_t *>(text.data()), text.size()),
      msime_client_string_free);
  if (!converted)
    return text;
  return std::string(converted.get());
}

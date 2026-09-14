#pragma once
#include "msime_client.h"
#include <memory>
#include <nlohmann/json.hpp>
#include <string>
#include <windows.h>

namespace msime::windows {
// Best-effort display conversion. Errors never erase a configured face.
inline std::wstring native_font_alias(const std::wstring &family) {
  try {
    if (family.empty() || family.size() > 128)
      return family;
    const int bytes = WideCharToMultiByte(
        CP_UTF8, WC_ERR_INVALID_CHARS, family.data(),
        static_cast<int>(family.size()), nullptr, 0, nullptr, nullptr);
    if (bytes <= 0 || bytes > 128)
      return family;
    std::string name(bytes, '\0');
    if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, family.data(),
                             static_cast<int>(family.size()), name.data(),
                             bytes, nullptr, nullptr))
      return family;
    const auto request = nlohmann::json::array({name}).dump();
    std::unique_ptr<char, decltype(&msime_client_string_free)> response(
        msime_client_resolve_font_families(
            reinterpret_cast<const uint8_t *>(request.data()), request.size()),
        msime_client_string_free);
    if (!response)
      return family;
    const auto document = nlohmann::json::parse(response.get());
    if (!document.value("ok", false) || !document.at("value").is_array() ||
        document.at("value").size() != 1)
      return family;
    const auto resolved = document.at("value").at(0).get<std::string>();
    if (resolved.empty() || resolved.size() > 128 ||
        resolved.find('\0') != std::string::npos)
      return family;
    const int count =
        MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, resolved.data(),
                            static_cast<int>(resolved.size()), nullptr, 0);
    if (count <= 0)
      return family;
    std::wstring result(count, L'\0');
    if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, resolved.data(),
                             static_cast<int>(resolved.size()), result.data(),
                             count))
      return family;
    return result;
  } catch (...) {
    return family;
  }
}
} // namespace msime::windows

#include "ChineseTextConversion.h"

#ifdef _WIN32
#include <windows.h>
#endif

namespace msime::windows {

#ifdef _WIN32
// LCMapStringEx takes a locale *name*, and Windows ships no LOCALE_NAME_ macro
// for Simplified Chinese - only the LOCALE_NAME_MAX_LENGTH bound and the three
// LOCALE_NAME_{INVARIANT,SYSTEM_DEFAULT,USER_DEFAULT} names. Spell it out.
constexpr const wchar_t *kSimplifiedChinese = L"zh-CN";
#endif

std::string simplified_to_traditional(std::string_view text,
                                      bool traditional_output) {
  if (!traditional_output || text.empty())
    return std::string(text);
#ifdef _WIN32
  if (text.size() > static_cast<size_t>(INT_MAX))
    return std::string(text);
  const int wide_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()),
      nullptr, 0);
  if (wide_length <= 0)
    return std::string(text);
  std::wstring wide(static_cast<size_t>(wide_length), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                          static_cast<int>(text.size()), wide.data(),
                          wide_length) != wide_length)
    return std::string(text);
  const int mapped_length = LCMapStringEx(
      kSimplifiedChinese, LCMAP_TRADITIONAL_CHINESE, wide.data(),
      wide_length, nullptr, 0, nullptr, nullptr, 0);
  if (mapped_length <= 0)
    return std::string(text);
  std::wstring mapped(static_cast<size_t>(mapped_length), L'\0');
  if (LCMapStringEx(kSimplifiedChinese,
                    LCMAP_TRADITIONAL_CHINESE, wide.data(), wide_length,
                    mapped.data(), mapped_length, nullptr, nullptr, 0) <=
      0)
    return std::string(text);
  const int utf8_length = WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, mapped.data(), mapped_length, nullptr, 0,
      nullptr, nullptr);
  if (utf8_length <= 0)
    return std::string(text);
  std::string result(static_cast<size_t>(utf8_length), '\0');
  if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, mapped.data(),
                          mapped_length, result.data(), utf8_length, nullptr,
                          nullptr) != utf8_length)
    return std::string(text);
  return result;
#else
  return std::string(text);
#endif
}

} // namespace msime::windows

#pragma once
#include <string>

namespace msime::windows {
// Best-effort display conversion. Errors never erase a configured face.
inline std::wstring native_font_alias(const std::wstring &family) { return family; }
} // namespace msime::windows

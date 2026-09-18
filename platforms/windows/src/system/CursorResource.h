#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

namespace msime::windows {
// IDC_* expand to MAKEINTRESOURCE(id), whose concrete type follows UNICODE:
// LPWSTR when it is defined, LPSTR when it is not. LoadCursorW needs the wide
// form, so wrapping the macro again is right for the narrow case but truncates
// an already-wide pointer through WORD in the wide case (C4302).
// Going through ULONG_PTR makes the intent explicit and is correct either way:
// both forms only ever carry the small integer id.
inline LPCWSTR wide_cursor(const void *system_cursor) noexcept {
  return MAKEINTRESOURCEW(
      static_cast<WORD>(reinterpret_cast<ULONG_PTR>(system_cursor)));
}
} // namespace msime::windows

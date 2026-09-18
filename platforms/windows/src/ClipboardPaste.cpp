#include "ClipboardPaste.h"
#include <stdexcept>
#ifdef _WIN32
#include <windows.h>
namespace msime::windows {
void paste_clipboard_text(const std::string &text) {
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (count <= 0 || !OpenClipboard(nullptr)) throw std::runtime_error("Clipboard unavailable");
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, static_cast<size_t>(count + 1) * sizeof(wchar_t));
  if (!memory) { CloseClipboard(); throw std::runtime_error("Clipboard allocation failed"); }
  auto *buffer = static_cast<wchar_t *>(GlobalLock(memory));
  if (!buffer || MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), buffer, count) != count) { if (buffer) GlobalUnlock(memory); GlobalFree(memory); CloseClipboard(); throw std::runtime_error("Clipboard conversion failed"); }
  buffer[count] = L'\0'; GlobalUnlock(memory); EmptyClipboard();
  if (!SetClipboardData(CF_UNICODETEXT, memory)) { GlobalFree(memory); CloseClipboard(); throw std::runtime_error("Clipboard write failed"); }
  CloseClipboard();
}
} // namespace msime::windows
#else
namespace msime::windows { void paste_clipboard_text(const std::string &) { throw std::runtime_error("Windows clipboard unavailable"); } }
#endif

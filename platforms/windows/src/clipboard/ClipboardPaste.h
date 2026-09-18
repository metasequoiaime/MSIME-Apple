#pragma once
#include "CandidateClickWorker.h"
#include <string>
namespace msime::windows {
struct ClipboardPaste { std::string text; };
using ClipboardPasteWorker = SingleClickWorker<ClipboardPaste>;
void paste_clipboard_text(const std::string &text);
} // namespace msime::windows

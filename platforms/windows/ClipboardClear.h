#pragma once
#include "CandidateClickWorker.h"
namespace msime::windows {
struct ClipboardClear {};
using ClipboardClearWorker = SingleClickWorker<ClipboardClear>;
}

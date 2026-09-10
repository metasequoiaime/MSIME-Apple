#pragma once
#include "CandidateClickWorker.h"
#include "ClipboardHistory.h"
namespace msime::windows {
struct ClipboardRemove { std::string text; };
using ClipboardRemoveWorker = SingleClickWorker<ClipboardRemove>;
}

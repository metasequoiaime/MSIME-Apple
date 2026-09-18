#pragma once

#include "../../../vendor/MSIME-Engine/contracts/windows_ipc.h"

#include <array>

namespace msime::windows {
// Installed TSF and Server share these fixed endpoints. Keep this choice
// separate from PreviewConfig so managed launches cannot inherit a development
// namespace accidentally.
inline std::array<std::wstring, 3> production_pipe_names() {
  return {FANY_IME_NAMED_PIPE, FANY_IME_TO_TSF_NAMED_PIPE,
          FANY_IME_TO_TSF_WORKER_THREAD_NAMED_PIPE};
}
} // namespace msime::windows

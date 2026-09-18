#include "../src/ToolbarModeCommand.h"
#include <cassert>
#include <tuple>
using namespace msime::windows;
int main() {
  for (const auto &[button, on, off] : {
      std::tuple{kToolbarLanguage, FanyImeWorkerReplyType::SwitchToEnglish,
                  FanyImeWorkerReplyType::SwitchToChinese},
      std::tuple{kToolbarFullwidth, FanyImeWorkerReplyType::SwitchToHalfwidth,
                  FanyImeWorkerReplyType::SwitchToFullwidth},
      std::tuple{kToolbarPunctuation, FanyImeWorkerReplyType::SwitchToPuncEn,
                  FanyImeWorkerReplyType::SwitchToPuncCn}}) {
    for (bool state : {false, true}) {
      // Only the selected button's state is required, not unrelated states.
      const auto mode = toolbar_mode_command(button,
          button == kToolbarLanguage ? std::optional{state} : std::nullopt,
          button == kToolbarFullwidth ? std::optional{state} : std::nullopt,
          button == kToolbarPunctuation ? std::optional{state} : std::nullopt);
      assert(mode);
      const auto bytes = worker_mode_bytes(*mode);
      assert(bytes && bytes->size() == sizeof(FanyImeNamedpipeDataToTsfWorkerThread));
      const uint32_t opcode = state ? on : off;
      for (size_t i = 0; i < 4; ++i)
        assert(bytes->at(i) == ((opcode >> (8 * i)) & 0xff));
      for (size_t i = 4; i < bytes->size(); ++i) assert(bytes->at(i) == 0);
    }
    assert(!toolbar_mode_command(button,
        button == kToolbarLanguage ? std::nullopt : std::optional{true},
        button == kToolbarFullwidth ? std::nullopt : std::optional{true},
        button == kToolbarPunctuation ? std::nullopt : std::optional{true}));
  }
  for (int button : {-1, 3, 4, 5, 6, 7, 8, 9, 10, 99})
    assert(!toolbar_mode_command(button, true, true, true));
}

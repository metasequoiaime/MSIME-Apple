#include "ReplyCodec.h"
#include "../../vendor/MSIME-Engine/contracts/windows_ipc.h"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("TSF config frame test failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
uint32_t frame_type(const std::vector<uint8_t> &frame) {
  uint32_t type = 0;
  for (size_t i = 0; i < sizeof(type); ++i)
    type |= static_cast<uint32_t>(frame[i]) << (8 * i);
  return type;
}
// The payload as the TIP reads it: a NUL-terminated wide string.
std::wstring frame_text(const std::vector<uint8_t> &frame) {
  const size_t offset = offsetof(FanyImeNamedpipeDataToTsfWorkerThread, data);
  std::wstring text;
  for (size_t i = offset; i + 1 < frame.size(); i += 2) {
    const auto unit = static_cast<wchar_t>(frame[i] | (frame[i + 1] << 8));
    if (!unit)
      break;
    text.push_back(unit);
  }
  return text;
}
} // namespace
int main() {
  try {
    TsfLocalConfig config;
    auto frames = tsf_config_frames(config);
    // Every setting the TIP consumes gets a frame; it kept compiled defaults
    // because the Server encoded none of them.
    require(frames.size() == 8);
    for (const auto &frame : frames)
      require(frame.size() == sizeof(FanyImeNamedpipeDataToTsfWorkerThread));

    // Each frame is the message type the TIP dispatches on, once each.
    const uint32_t expected[] = {
        FanyImeWorkerReplyType::PagingCommaPeriodChanged,
        FanyImeWorkerReplyType::SmartPunctuationChanged,
        FanyImeWorkerReplyType::SmartPunctuationRepeatToChineseChanged,
        FanyImeWorkerReplyType::PairedPunctuationChanged,
        FanyImeWorkerReplyType::MicrosoftShuangpinChanged,
        FanyImeWorkerReplyType::InputModeChanged,
        FanyImeWorkerReplyType::TsfDiagnosticLogChanged,
        FanyImeWorkerReplyType::PunctuationLockChanged};
    for (size_t i = 0; i < frames.size(); ++i)
      require(frame_type(frames[i]) == expected[i]);

    // Booleans travel as "1"/"0", which is what the TIP compares against.
    config.smart_punctuation = false;
    config.paired_punctuation = true;
    config.microsoft_shuangpin = true;
    frames = tsf_config_frames(config);
    require(frame_text(frames[1]) == L"0"); // smart punctuation off
    require(frame_text(frames[3]) == L"1"); // paired punctuation on
    require(frame_text(frames[4]) == L"1"); // Microsoft shuangpin on

    // The preedit style rides along with the paging frame after a '|'; there is
    // no separate message type for it, which is why it stayed stuck at raw.
    config.paging_comma_period = true;
    config.preedit_style = "pinyin";
    frames = tsf_config_frames(config);
    require(frame_text(frames[0]) == L"1|pinyin");
    config.paging_comma_period = false;
    config.preedit_style = "empty";
    require(frame_text(tsf_config_frames(config)[0]) == L"0|empty");
    // An unknown style is omitted rather than forwarded, so the TIP keeps its
    // own value instead of being handed something it cannot parse.
    config.preedit_style = "nonsense";
    require(frame_text(tsf_config_frames(config)[0]) == L"0");

    // Punctuation lock is a digit: follow / always Chinese / always English.
    for (uint8_t lock = 0; lock < 3; ++lock) {
      config.punctuation_lock = lock;
      const auto text = frame_text(tsf_config_frames(config)[7]);
      require(text.size() == 1 && text[0] == static_cast<wchar_t>(L'0' + lock));
    }

    std::cout << "TSF config frames: every setting the TIP reads is encoded\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "TSF config frame test failed with an unknown error\n";
    return 1;
  }
}

#pragma once
#include <functional>
#include <string>

inline std::string msime_voice_bound_result(std::string value,
                                            std::size_t limit = 4096) {
  if (value.size() <= limit)
    return value;
  value.resize(limit);
  while (!value.empty() && (static_cast<unsigned char>(value.back()) & 0xc0) == 0x80)
    value.pop_back();
  return value;
}

// Platform adapter contract: implementations run capture/provider work off
// the IBus thread and deliver only bounded UTF-8 results back to the host.
struct MsimeVoiceAction {
  using Submit = std::function<void(std::string)>;
  virtual ~MsimeVoiceAction() = default;
  virtual bool start(Submit result) = 0;
  virtual void cancel() = 0;
};

#pragma once
#include <functional>
#include <string>

// Platform adapter contract: implementations run capture/provider work off
// the IBus thread and deliver only bounded UTF-8 results back to the host.
struct MsimeVoiceAction {
  using Submit = std::function<void(std::string)>;
  virtual ~MsimeVoiceAction() = default;
  virtual bool start(Submit result) = 0;
  virtual void cancel() = 0;
};

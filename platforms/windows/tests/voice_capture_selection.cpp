#include "../VoiceCaptureSelection.h"
#include <cassert>

int main() {
  using namespace msime::windows;
  const auto defaults = voice_capture_selection(nlohmann::json::object());
  assert(defaults.supported() && defaults.device_id.empty());
  for (const auto *backend : {"", "auto", "windows"}) {
    const auto selected = voice_capture_selection({{"capture_backend", backend},
                                                  {"capture_device", "wasapi:0061"}});
    assert(selected.supported() && selected.device_id == "wasapi:0061");
  }
  for (const auto *backend : {"pulse", "pipewire", "alsa", "macos", "unknown"})
    assert(!voice_capture_selection({{"capture_backend", backend}}).supported());
  // Do not reinterpret an old ordinal as a new endpoint or silently clear it.
  // The Engine rejects this id before opening a device.
  assert(voice_capture_selection({{"capture_device", "0"}}).device_id == "0");
}

#include "../WaveOverlayModel.h"
#include "../WaveOverlayIbusSurface.h"
#include "../WaveOverlaySurfaceFactory.h"
#include "../VoiceAction.h"
#include <cassert>
#include <cstdlib>

int main() {
  msime::linux_host::WaveOverlayModel model;
  model.set_input_level(2.0f);
  for (float level : model.levels) assert(level >= 0.0f && level <= 1.0f);
  model.set_input_level(-1.0f);
  for (float level : model.levels) assert(level == 0.0f);
  model.set_transcript(std::string(200, 'a'));
  assert(model.transcript.size() == 160);
  std::string han;
  for (int i = 0; i < 200; ++i) han += "你";
  model.set_transcript(han);
  assert(model.transcript.size() == 160 * 3);
  model.status = "正在识别…";
  model.listening = true;
  model.set_input_level(1.0f);
  const auto feedback = msime::linux_host::wave_overlay_feedback_text(model);
  assert(feedback.find("正在识别…") == 0);
  assert(feedback.find("麦克风 [") != std::string::npos);
  model.transcript = "第一行\n第二行";
  const auto sanitized = msime::linux_host::wave_overlay_feedback_text(model);
  assert(sanitized.find("第一行 第二行") != std::string::npos);
  model.locked = true;
  const auto locked = msime::linux_host::wave_overlay_feedback_text(model);
  assert(locked.find("录音已锁定") == 0);
  assert(locked.find("麦克风 [") == std::string::npos);
  unsetenv("MSIME_WAVE_OVERLAY_BACKEND");
  unsetenv("DISPLAY");
  unsetenv("WAYLAND_DISPLAY");
  assert(msime::linux_host::create_wave_overlay_surface(nullptr));
  assert(msime_voice_stream_inline_enabled(true, "doubao"));
  assert(msime_voice_stream_inline_enabled(true, "doubao", "tsf"));
  assert(msime_voice_stream_inline_enabled(true, "doubao", ""));
  assert(!msime_voice_stream_inline_enabled(true, "doubao", "sendinput"));
  assert(!msime_voice_stream_inline_enabled(true, "doubao", "ctrl_v"));
  assert(!msime_voice_stream_inline_enabled(true, "openai"));
  assert(!msime_voice_stream_inline_enabled(false, "doubao"));
}

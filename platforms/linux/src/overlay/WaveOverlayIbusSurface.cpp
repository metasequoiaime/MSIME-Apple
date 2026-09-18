#include "WaveOverlayIbusSurface.h"

#include <ibus.h>

#include <algorithm>
#include <string>

namespace msime::linux_host {
std::string wave_overlay_feedback_text(const WaveOverlayModel &model) {
  std::string feedback = model.status;
  if (feedback.empty()) {
    switch (model.compact_status) {
      case WaveOverlayModel::CompactStatus::Recognizing:
        feedback = "正在识别…";
        break;
      case WaveOverlayModel::CompactStatus::Processing:
        feedback = "正在处理…";
        break;
      case WaveOverlayModel::CompactStatus::None:
        feedback = "正在录音…";
        break;
    }
  }
  if (model.locked)
    feedback = "录音已锁定 · 可松开快捷键 · 再按快捷键或点击语音菜单结束 · Esc 取消";
  if (model.listening && !model.locked) {
    feedback += "  麦克风 [";
    for (std::size_t index = 0; index < 10; ++index)
      feedback += (index < model.levels.size() && model.levels[index] >= 0.08f)
                      ? "▰"
                      : "▱";
    feedback += "]";
  }
  if (model.show_transcript && !model.transcript.empty()) {
    const auto length = g_utf8_strlen(model.transcript.c_str(), -1);
    const auto *tail = g_utf8_offset_to_pointer(
        model.transcript.c_str(), std::max<glong>(0, length - 160));
    std::string preview(tail);
    for (auto &character : preview)
      if (character == '\r' || character == '\n' || character == '\t')
        character = ' ';
    feedback += "\n";
    if (length > 160)
      feedback += "…";
    feedback += preview;
  }
  return feedback;
}

bool WaveOverlayIbusSurface::show(const WaveOverlayModel &model) {
  if (!engine_)
    return false;
  visible_ = true;
  update(model);
  return true;
}

void WaveOverlayIbusSurface::update(const WaveOverlayModel &model) {
  if (!engine_ || !visible_)
    return;
  const auto feedback = wave_overlay_feedback_text(model);
  ibus_engine_update_auxiliary_text(
      engine_, ibus_text_new_from_string(feedback.c_str()), TRUE);
}

void WaveOverlayIbusSurface::hide() {
  if (engine_ && visible_)
    ibus_engine_hide_auxiliary_text(engine_);
  visible_ = false;
}

}  // namespace msime::linux_host

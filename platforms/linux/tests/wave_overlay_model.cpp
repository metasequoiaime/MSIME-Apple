#include "../WaveOverlayModel.h"
#include <cassert>

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
}

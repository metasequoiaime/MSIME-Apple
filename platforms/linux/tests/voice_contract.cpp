#include <msime/voice/provider_protocol.h>
#include <msime/voice/vad.h>

#include <cassert>
#include <string>
#include <vector>

int main()
{
  using namespace metasequoia::voice;
  const auto request = make_polish_request("demo-model", "Keep UTF-8", "水杉");
  assert(request.find("demo-model") != std::string::npos);
  assert(request.find("水杉") != std::string::npos);

  VadSegmenter vad;
  vad.process(std::vector<float>(16000 / 100, 0.0F).data(), 16000 / 100);
  assert(vad.take_audio().empty());
  return 0;
}

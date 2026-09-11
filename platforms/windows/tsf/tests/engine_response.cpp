#include "../EngineSessionAdapter.h"

#include <cstdlib>

using msime::tsf::EngineResult;
using msime::tsf::EngineSessionAdapter;

int main() {
  EngineResult result;
  std::string error;
  const std::string response =
      R"({"ok":true,"value":{"handled":true,"has_commit":true,"commit":"你","diagnostic":"","view":{"preedit":"ni","editing_text":"ni","caret":1,"candidates":[{"id":{"generation":7,"index":0},"text":"你"}]}}})";
  if (!EngineSessionAdapter::parse_result(response, &result, &error) ||
      !result.handled || !result.has_commit || result.commit != "你" ||
      result.view.generation != 7 || result.view.caret != 1 || result.view.candidates.size() != 1 ||
      result.view.candidates[0].text != "你")
    return EXIT_FAILURE;
  if (EngineSessionAdapter::parse_result(
          R"({"ok":false,"error":"redacted"})", &result, &error))
    return EXIT_FAILURE;
  return EXIT_SUCCESS;
}

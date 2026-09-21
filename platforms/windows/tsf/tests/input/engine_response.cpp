#include "../../EngineSessionAdapter.h"
#include "../../../../../shared/input/CompositionDisplay.h"

#include <cstdlib>

using msime::tsf::EngineResult;
using msime::tsf::EngineSessionAdapter;

int main() {
  EngineResult result;
  std::string error;
  const std::string response =
      R"({"ok":true,"value":{"handled":true,"commit":"你","diagnostic":null,"view":{"preedit":"ni","editing_text":"ni","caret_position":1,"candidates":[{"id":{"generation":7,"index":12},"text":"你","highlighted":true}]}}})";
  if (!EngineSessionAdapter::parse_result(response, &result, &error) ||
      !result.handled || !result.has_commit || result.commit != "你" ||
      result.view.generation != 7 || result.view.caret != 1 || result.view.candidates.size() != 1 ||
      result.view.candidates[0].text != "你" ||
      result.view.candidates[0].index != 12 || !result.view.candidates[0].highlighted)
    return EXIT_FAILURE;
  // A Japanese composition carries the kana the letters convert to. The composition shows that
  // rather than the letters, so a parser that dropped it would leave the TIP drawing romaji with
  // no way to tell.
  {
    EngineResult japanese;
    const std::string kana =
        R"({"ok":true,"value":{"handled":true,"commit":null,"view":{"preedit":"nihon","editing_text":"nihon","reading":"にほん","caret_position":5}}})";
    if (!EngineSessionAdapter::parse_result(kana, &japanese, &error) ||
        japanese.view.reading != "にほん" || japanese.view.editing_text != "nihon")
      return EXIT_FAILURE;
    if (!msime::input::composition_shows_reading(japanese.view.reading, japanese.view.caret,
                                                 japanese.view.editing_text.size()))
      return EXIT_FAILURE;
    // Every other scheme leaves it empty, and then the letters are what there is.
    if (!result.view.reading.empty() ||
        msime::input::composition_shows_reading(result.view.reading, result.view.caret,
                                                result.view.editing_text.size()))
      return EXIT_FAILURE;
  }
  if (EngineSessionAdapter::parse_result(
          R"({"ok":false,"error":"redacted"})", &result, &error))
    return EXIT_FAILURE;
  if (!EngineSessionAdapter::parse_result(
        R"({"ok":true,"value":{"session":17,"preedit":"test","editing_text":"test","caret_position":3,"generation":9,"candidates":[]}})",
        &result, &error) || result.view.caret != 3 || result.view.generation != 9 ||
      result.view.preedit != "test" || result.view.session != 17 || result.has_commit) return EXIT_FAILURE;
  if (!EngineSessionAdapter::parse_result(
        R"({"ok":true,"value":{"handled":true,"commit":null,"diagnostic":null,"view":{"preedit":"","candidates":[]}}})",
        &result, &error) || result.has_commit || !result.diagnostic.empty()) return EXIT_FAILURE;
  return EXIT_SUCCESS;
}

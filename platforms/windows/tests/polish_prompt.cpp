#include "PolishPrompt.h"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("Polish prompt test failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
} // namespace
int main() {
  try {
    // The defect: a non-empty legacy box used to win before the slot was even
    // looked at, so picking 自定义二 still sent the legacy text - while the
    // Linux host and the reference both sent slot two.
    PolishPromptSlots slots;
    slots.legacy = "legacy text";
    slots.custom_2 = "slot two";
    slots.id = "custom_2";
    require(polish_prompt_for(slots) == "slot two");
    slots.id = "custom_3";
    slots.custom_3 = "slot three";
    require(polish_prompt_for(slots) == "slot three");

    // Only the first slot falls back to the legacy box, which is where an
    // older configuration's single prompt lived.
    PolishPromptSlots first;
    first.id = "custom_1";
    first.legacy = "legacy text";
    require(polish_prompt_for(first) == "legacy text");
    first.custom_1 = "slot one";
    require(polish_prompt_for(first) == "slot one");
    // "custom" is the legacy spelling of the first slot.
    first.id = "custom";
    require(polish_prompt_for(first) == "slot one");

    // An empty second or third slot does NOT fall back to the legacy box: that
    // box belongs to slot one, and borrowing it would send the wrong prompt.
    PolishPromptSlots empty_slot;
    empty_slot.id = "custom_2";
    empty_slot.legacy = "legacy text";
    require(polish_prompt_for(empty_slot) != "legacy text");
    require(!polish_prompt_for(empty_slot).empty());
    empty_slot.id = "custom_3";
    require(polish_prompt_for(empty_slot) != "legacy text");

    // With a preset selected, a legacy prompt still overrides the built-in
    // text, so a configuration that only ever set polish_prompt keeps working.
    PolishPromptSlots preset;
    preset.id = "faithful";
    preset.legacy = "legacy text";
    require(polish_prompt_for(preset) == "legacy text");
    preset.legacy.clear();
    const auto faithful = polish_prompt_for(preset);
    require(faithful.find("<asr_text>") != std::string::npos);

    // Each preset resolves to its own multi-rule text, and they differ.
    PolishPromptSlots plain;
    std::string previous;
    for (const char *id : {"cleanup", "faithful", "zh2en", "casual"}) {
      plain.id = id;
      const auto prompt = polish_prompt_for(plain);
      require(prompt.size() > 100);
      require(prompt != previous);
      previous = prompt;
    }
    // An unknown id falls back to the default preset rather than an empty
    // prompt, which would send the model no instruction at all.
    plain.id = "nonsense";
    require(!polish_prompt_for(plain).empty());
    plain.id.clear();
    require(!polish_prompt_for(plain).empty());

    std::cout << "Polish prompt: the selected slot decides first\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Polish prompt test failed with an unknown error\n";
    return 1;
  }
}

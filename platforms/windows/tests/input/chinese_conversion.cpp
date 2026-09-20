// Pin what simplified-to-traditional conversion guarantees, without pinning the mapping table.
//
// This host converts with LCMapStringEx(LCMAP_TRADITIONAL_CHINESE), so the mapping belongs to the
// operating system and moves with it. Asserting particular traditional forms would be asserting a
// Windows version, and under Wine it would assert Wine's table. What is this code's own behaviour -
// and therefore what is worth a test - is the surrounding contract: the switch, the untouched
// inputs, and never losing text when anything goes wrong.
#include "ChineseTextConversion.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Chinese conversion fixture failed at line " +
                             std::to_string(line));
}
#define require(...) require_at((__VA_ARGS__), __LINE__)
} // namespace

int main() {
  try {
    // The switch is off: nothing is converted, whatever the text.
    require(simplified_to_traditional("国家", false) == "国家");
    require(simplified_to_traditional("", false).empty());

    // Empty input stays empty rather than reaching the platform call.
    require(simplified_to_traditional("", true).empty());

    // ASCII has no traditional form and has to survive byte for byte, including text that a
    // character-by-character mapper could mangle if it ran over it.
    for (const char *text : {"abc", "ASCII 123", "a,b.c", "\t\n"})
      require(simplified_to_traditional(text, true) == text);

    // Invalid UTF-8 cannot be converted. Returning the input is the documented fallback; the one
    // thing that must never happen is losing the text or throwing out of here.
    const std::string invalid("\xff\xfe invalid", 11);
    require(simplified_to_traditional(invalid, true) == invalid);

    // Conversion never empties non-empty text. Off Windows this is the identity, which is the
    // point: the fallback path has to be a passthrough rather than a silent drop.
    const std::string simplified = "国家学习";
    const auto converted = simplified_to_traditional(simplified, true);
    require(!converted.empty());
    // Whatever the table says, the result stays well-formed UTF-8 of the same character count.
    size_t characters = 0;
    for (unsigned char unit : converted)
      if ((unit & 0xC0) != 0x80)
        ++characters;
    require(characters == 4);

    std::cout << "Chinese conversion contract holds\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

#include "AuxMessage.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <cstring>
#include <optional>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Aux message test failed at line " +
                             std::to_string(line));
}
// Reproduce exactly what the TSF DLL writes: the raw code units, no NUL.
std::vector<char> wire(const std::wstring &text) {
  std::vector<char> bytes(text.size() * sizeof(wchar_t));
  if (!text.empty())
    std::memcpy(bytes.data(), text.data(), bytes.size());
  return bytes;
}
std::optional<AuxLangbarRightClick> decode(const std::wstring &text) {
  const auto bytes = wire(text);
  const auto decoded = aux_text_from_bytes(bytes.data(), bytes.size());
  if (!decoded)
    return std::nullopt;
  return parse_aux_langbar_right_click(*decoded);
}
} // namespace
#define require(...) require_at((__VA_ARGS__), __LINE__)

int main() {
  try {
    // The message the language bar actually sends.
    const auto click = decode(L"LangbarRightClick|100|200|140|240");
    require(click.has_value());
    require(click->left == 100 && click->top == 200);
    require(click->right == 140 && click->bottom == 240);
    const auto anchor = tray_menu_anchor(*click);
    require(anchor.center_x == 120 && anchor.top == 200);

    // A secondary monitor left of or above the primary gives negative screen
    // coordinates, which are legitimate.
    const auto negative = decode(L"LangbarRightClick|-1920|-100|-1880|-60");
    require(negative.has_value());
    require(tray_menu_anchor(*negative).center_x == -1900);
    require(tray_menu_anchor(*negative).top == -100);

    // The centre must not be computed as (left + right) / 2.
    const auto far_right = decode(L"LangbarRightClick|2000000000|10|2000000040|50");
    require(far_right.has_value());
    require(tray_menu_anchor(*far_right).center_x == 2000000020);

    // The other three Aux verbs are not this message and must not parse.
    require(!decode(L"IMEActivation"));
    require(!decode(L"IMEDeactivation"));
    require(!decode(L"TerminalDeactivation|123|456"));

    // Malformed rectangles.
    require(!decode(L"LangbarRightClick|100|200|100|240"));
    require(!decode(L"LangbarRightClick|100|200|140|200"));
    require(!decode(L"LangbarRightClick|0|0|5000|40"));
    require(!decode(L"LangbarRightClick|0|0|40|5000"));

    // Malformed fields.
    require(!decode(L"LangbarRightClick"));
    require(!decode(L"LangbarRightClick|1|2|3"));
    require(!decode(L"LangbarRightClick|1|2|3|4|5"));
    require(!decode(L"LangbarRightClick|1|2|3|x"));
    require(!decode(L"LangbarRightClick|1|2|3|"));
    require(!decode(L"LangbarRightClick|1|2|3|+4"));
    require(!decode(L"LangbarRightClick|1|2|3|99999999999"));
    require(!decode(L"langbarrightclick|100|200|140|240"));
    require(!decode(L"LangbarRightClickX|100|200|140|240"));

    // Envelope rejections, before any parsing happens.
    require(!aux_text_from_bytes(nullptr, 8));
    const auto empty = wire(L"");
    require(!aux_text_from_bytes(empty.data(), 0));
    const auto valid = wire(L"LangbarRightClick|100|200|140|240");
    // An odd byte count is a truncated code unit.
    require(!aux_text_from_bytes(valid.data(), valid.size() - 1));
    // Longer than any real message.
    std::vector<char> oversized(max_aux_message_bytes + 2, 'a');
    require(!aux_text_from_bytes(oversized.data(), oversized.size()));
    // An embedded NUL would let a prefix parse as the whole message.
    auto embedded = wire(L"LangbarRightClick|1|2|3|4");
    embedded[2] = 0;
    require(!aux_text_from_bytes(embedded.data(), embedded.size()));
    const auto newline = wire(L"LangbarRightClick|1|2|3|4\n");
    require(!aux_text_from_bytes(newline.data(), newline.size()));

    // The activation edges. "Mode view is empty" is not "the IME is off": a
  // temporary focus suspension empties the view without deactivating anything,
  // and gating the toolbar on the view alone made it blink away every time.
  require(parse_aux_activation(L"IMEActivation") == AuxActivation::Activated);
  require(parse_aux_activation(L"IMEDeactivation") == AuxActivation::Deactivated);
  require(!parse_aux_activation(L"IMEActivation|1"));
  require(!parse_aux_activation(L"imeactivation"));
  require(!parse_aux_activation(L""));
  require(!parse_aux_activation(L"LangbarRightClick|1|2|3|4"));

  // TerminalDeactivation carries a client id and a focus token, both positive.
  const auto terminal = parse_aux_terminal_deactivation(L"TerminalDeactivation|7|42");
  require(terminal && terminal->client_id == 7 && terminal->focus_token == 42);
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|7"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|7|42|9"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|0|42"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|7|0"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|-1|42"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation|a|42"));
  require(!parse_aux_terminal_deactivation(L"TerminalDeactivation"));
  require(!parse_aux_terminal_deactivation(L"IMEActivation"));
  // The verbs never claim each other's messages.
  require(!parse_aux_langbar_right_click(L"TerminalDeactivation|7|42"));
  require(!parse_aux_terminal_deactivation(L"LangbarRightClick|1|2|3|4"));

  std::cout << "Aux message: langbar rectangle parsed, malformed rejected\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}

#pragma once
#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace msime::windows {
// The TSF DLL writes Aux messages as the raw UTF-16 code units of a string with
// no length prefix, no magic and no NUL terminator: the byte count is
// length * sizeof(wchar_t) (tsf/IPC/Ipc.cpp:1449-1456). Framing therefore comes
// from the message-mode pipe, one WriteFile per message.
inline constexpr size_t max_aux_message_bytes = 256;

// The langbar right-click rectangle, in screen coordinates, as TSF hands it to
// ITfLangBarItemButton::OnClick.
struct AuxLangbarRightClick {
  int32_t left = 0;
  int32_t top = 0;
  int32_t right = 0;
  int32_t bottom = 0;
};

// Where the tray card should be anchored: the icon's horizontal centre and its
// top edge, which is what TrayMenuWindow::show expects.
struct TrayMenuAnchor {
  int center_x = 0;
  int top = 0;
};

// Decode the wire bytes. This is untrusted, session-less input, so every
// rejection is explicit and nothing is assumed about termination.
inline std::optional<std::wstring> aux_text_from_bytes(const void *bytes,
                                                       size_t size) {
  if (!bytes || size == 0 || size > max_aux_message_bytes ||
      size % sizeof(wchar_t) != 0)
    return std::nullopt;
  const auto *units = static_cast<const wchar_t *>(bytes);
  std::wstring text(units, size / sizeof(wchar_t));
  for (wchar_t unit : text)
    // A control character cannot appear in any message the DLL sends, and an
    // embedded NUL would let a prefix parse as if it were the whole message.
    if (unit < 0x20 || unit == 0x7f)
      return std::nullopt;
  return text;
}

namespace detail {
// Parse one decimal field. Rejects empty, signs other than a leading '-',
// non-digits, and anything that would overflow int32.
inline std::optional<int32_t> aux_field(std::wstring_view field) {
  if (field.empty() || field.size() > 11)
    return std::nullopt;
  bool negative = false;
  size_t index = 0;
  if (field[0] == L'-') {
    negative = true;
    index = 1;
    if (field.size() == 1)
      return std::nullopt;
  }
  int64_t value = 0;
  for (; index < field.size(); ++index) {
    const wchar_t unit = field[index];
    if (unit < L'0' || unit > L'9')
      return std::nullopt;
    value = value * 10 + (unit - L'0');
    if (value > 2147483647LL)
      return std::nullopt;
  }
  return static_cast<int32_t>(negative ? -value : value);
}
} // namespace detail

// Largest rectangle accepted for a language-bar button. Anything wider is not a
// button and is more likely a malformed or hostile message.
inline constexpr int32_t max_aux_extent = 4096;

inline std::optional<AuxLangbarRightClick>
parse_aux_langbar_right_click(const std::wstring &text) {
  static constexpr std::wstring_view verb = L"LangbarRightClick";
  if (text.size() <= verb.size() || text.compare(0, verb.size(), verb) != 0 ||
      text[verb.size()] != L'|')
    return std::nullopt;
  std::vector<std::wstring_view> fields;
  std::wstring_view rest(text);
  rest.remove_prefix(verb.size() + 1);
  while (true) {
    const auto separator = rest.find(L'|');
    if (separator == std::wstring_view::npos) {
      fields.push_back(rest);
      break;
    }
    fields.push_back(rest.substr(0, separator));
    rest.remove_prefix(separator + 1);
    // Four coordinates is the whole message; more means it is not this verb.
    if (fields.size() > 4)
      return std::nullopt;
  }
  if (fields.size() != 4)
    return std::nullopt;
  AuxLangbarRightClick click;
  int32_t *slots[] = {&click.left, &click.top, &click.right, &click.bottom};
  for (size_t index = 0; index < fields.size(); ++index) {
    const auto value = detail::aux_field(fields[index]);
    if (!value)
      return std::nullopt;
    *slots[index] = *value;
  }
  if (click.right <= click.left || click.bottom <= click.top)
    return std::nullopt;
  if (click.right - click.left > max_aux_extent ||
      click.bottom - click.top > max_aux_extent)
    return std::nullopt;
  return click;
}

// The activation edges the TSF DLL reports.
//
// These matter because "the mode view is empty" is not the same thing as "the
// IME is off": a temporary thread-focus suspension - Win+. opening the emoji
// panel, for instance - empties the view without deactivating anything. Gating
// the floating toolbar on the view alone made it blink away on every such
// suspension. The reference warns about exactly this and tracks the edges.
enum class AuxActivation { Activated, Deactivated };
inline std::optional<AuxActivation> parse_aux_activation(const std::wstring &text) {
  if (text == L"IMEActivation")
    return AuxActivation::Activated;
  if (text == L"IMEDeactivation")
    return AuxActivation::Deactivated;
  return std::nullopt;
}

// TerminalDeactivation|<clientId>|<focusToken>
//
// The DLL falls back to this when its Main-pipe deactivate write fails, and
// then polls the Aux pipe for a literal "OK" for up to 150 ms. Leaving it
// unanswered blocks the sending TSF thread for that whole window.
struct AuxTerminalDeactivation {
  int32_t client_id = 0;
  int32_t focus_token = 0;
};
inline std::optional<AuxTerminalDeactivation>
parse_aux_terminal_deactivation(const std::wstring &text) {
  static constexpr std::wstring_view verb = L"TerminalDeactivation";
  if (text.size() <= verb.size() || text.compare(0, verb.size(), verb) != 0 ||
      text[verb.size()] != L'|')
    return std::nullopt;
  std::wstring_view rest(text);
  rest.remove_prefix(verb.size() + 1);
  const auto separator = rest.find(L'|');
  if (separator == std::wstring_view::npos)
    return std::nullopt;
  const auto client = detail::aux_field(rest.substr(0, separator));
  const auto token = detail::aux_field(rest.substr(separator + 1));
  if (!client || !token)
    return std::nullopt;
  // Both identifiers are positive on the wire; zero or negative means the DLL
  // never had a real client, so there is nothing to deactivate.
  if (*client <= 0 || *token <= 0)
    return std::nullopt;
  return AuxTerminalDeactivation{*client, *token};
}

// Anchor the card on the button. The centre is computed as left + width / 2
// rather than (left + right) / 2 so a rectangle far from the origin cannot
// overflow on the way.
inline TrayMenuAnchor tray_menu_anchor(const AuxLangbarRightClick &click) {
  return {click.left + (click.right - click.left) / 2, click.top};
}
} // namespace msime::windows

#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace msime::windows {
// The CN/EN and 简繁 hotkeys, as the TIP reads them.
//
// These four live in the shared config.toml rather than on the worker pipe,
// because the TIP reads them directly at activation - see
// ReadConfiguredSwitchLanguageHotkeys. The settings page owns them, so the
// Server has to mirror them into that file or the toggles save and do nothing,
// which is exactly why they were hidden on Windows until now.
struct SwitchLanguageKeybindings {
  bool shift = true;
  bool ctrl = false;
  bool ctrl_alt_space = true;
  bool character_set_ctrl_shift_f = true;
};

namespace detail {
inline std::string_view trim_ascii(std::string_view text) {
  const auto first = text.find_first_not_of(" \t\r\n");
  if (first == std::string_view::npos)
    return {};
  return text.substr(first, text.find_last_not_of(" \t\r\n") - first + 1);
}

// The key this line assigns, or empty if it assigns nothing. Comments are
// stripped the same way the TIP strips them, so a commented-out key is not
// mistaken for a live one and left to shadow the value we write.
inline std::string_view assigned_key(std::string_view line) {
  const auto comment = line.find('#');
  if (comment != std::string_view::npos)
    line = line.substr(0, comment);
  const auto equals = line.find('=');
  if (equals == std::string_view::npos)
    return {};
  return trim_ascii(line.substr(0, equals));
}

// The section this line opens, or empty if it opens none.
inline std::string_view section_header(std::string_view line) {
  const auto comment = line.find('#');
  if (comment != std::string_view::npos)
    line = line.substr(0, comment);
  const auto trimmed = trim_ascii(line);
  if (trimmed.size() < 2 || trimmed.front() != '[' || trimmed.back() != ']')
    return {};
  return trimmed;
}
} // namespace detail

// Rewrite the [keybindings] section of `existing`, preserving everything else.
//
// Everything outside the four keys is kept verbatim - other sections, ordering,
// comments, and the legacy `switch_language` array, which the TIP already
// ignores once the explicit keys are present. A user's hand-edited config has
// to survive this; we are a guest in their file.
inline std::string update_keybindings(std::string_view existing,
                                      const SwitchLanguageKeybindings &values) {
  struct Entry {
    std::string_view key;
    bool value;
  };
  const Entry entries[] = {
      {"switch_language_shift", values.shift},
      {"switch_language_ctrl", values.ctrl},
      {"switch_language_ctrl_alt_space", values.ctrl_alt_space},
      {"toggle_character_set_ctrl_shift_f", values.character_set_ctrl_shift_f}};

  // Split into lines, remembering whether the file used CRLF, so writing it
  // back does not convert a user's whole config to the other convention.
  const bool crlf = existing.find("\r\n") != std::string_view::npos;
  std::vector<std::string_view> lines;
  size_t start = 0;
  while (start <= existing.size()) {
    auto end = existing.find('\n', start);
    if (end == std::string_view::npos) {
      lines.push_back(existing.substr(start));
      break;
    }
    auto line = existing.substr(start, end - start);
    if (!line.empty() && line.back() == '\r')
      line.remove_suffix(1);
    lines.push_back(line);
    start = end + 1;
  }
  // A file ending in a newline yields a trailing empty piece; drop it so the
  // terminator is decided in one place below.
  if (!lines.empty() && lines.back().empty())
    lines.pop_back();

  std::vector<std::string> output;
  output.reserve(lines.size() + 6);
  bool in_section = false;
  bool section_seen = false;
  bool written[std::size(entries)] = {};
  // Where to append keys the section did not already have: the end of the
  // section's own lines, not the end of the file, or they would land under
  // whatever section happens to come last.
  size_t append_at = 0;

  for (const auto &line : lines) {
    if (const auto header = detail::section_header(line); !header.empty()) {
      if (in_section)
        append_at = output.size();
      in_section = header == "[keybindings]";
      if (in_section)
        section_seen = true;
      output.emplace_back(line);
      continue;
    }
    if (in_section) {
      const auto key = detail::assigned_key(line);
      bool replaced = false;
      for (size_t i = 0; i < std::size(entries); ++i) {
        if (key != entries[i].key)
          continue;
        // Keep the first assignment's position and drop any later duplicate,
        // so the file cannot end up with two values for one key.
        if (!written[i]) {
          output.emplace_back(std::string(entries[i].key) + " = " +
                              (entries[i].value ? "true" : "false"));
          written[i] = true;
        }
        replaced = true;
        break;
      }
      if (!replaced)
        output.emplace_back(line);
      continue;
    }
    output.emplace_back(line);
  }
  if (in_section)
    append_at = output.size();

  std::vector<std::string> missing;
  if (!section_seen)
    missing.emplace_back("[keybindings]");
  for (size_t i = 0; i < std::size(entries); ++i)
    if (!written[i])
      missing.emplace_back(std::string(entries[i].key) + " = " +
                           (entries[i].value ? "true" : "false"));
  if (!missing.empty()) {
    if (!section_seen) {
      // A new section goes at the end, after a blank line if the file did not
      // already end with one.
      if (!output.empty() && !detail::trim_ascii(output.back()).empty())
        output.emplace_back("");
      append_at = output.size();
    }
    output.insert(output.begin() + static_cast<std::ptrdiff_t>(append_at),
                  missing.begin(), missing.end());
  }

  std::string result;
  for (const auto &line : output) {
    result += line;
    result += crlf ? "\r\n" : "\n";
  }
  return result;
}
} // namespace msime::windows

#pragma once
#include "TrayMenuLayout.h"
#include <cwctype>
#include <filesystem>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace msime::windows {
// What a tray entry asks the shared desktop shell to open. The shell is the
// Tauri application both desktop hosts share: the IBus property menu launches
// it through the same environment contract, so a surface exists once and both
// hosts point at it instead of growing a second implementation.
struct ShellSurfaceRequest {
  // MSIME_CLIENT_PANEL value. Empty opens the settings window itself.
  std::string panel;
  // MSIME_CLIENT_SETTINGS_PAGE value. Empty keeps the settings default section.
  std::string page;
};
// The floating toolbar belongs to this process, so it is the one row the shell
// never hears about.
inline std::optional<ShellSurfaceRequest>
shell_surface_request(TrayMenuCommand command) {
  switch (command) {
  case TrayMenuCommand::OpenEmojiPanel:
    return ShellSurfaceRequest{"emoji", {}};
  case TrayMenuCommand::OpenHandwritingPanel:
    return ShellSurfaceRequest{"handwriting", {}};
  case TrayMenuCommand::OpenKeyboardPanel:
    return ShellSurfaceRequest{"keyboard", {}};
  case TrayMenuCommand::ToggleVoiceInput:
    return ShellSurfaceRequest{"voice", {}};
  case TrayMenuCommand::OpenSettings:
    return ShellSurfaceRequest{{}, {}};
  case TrayMenuCommand::OpenAbout:
    return ShellSurfaceRequest{{}, "about"};
  case TrayMenuCommand::ToggleFloatingToolbar:
    break;
  }
  return std::nullopt;
}
// File names the package stages beside the Server. The installer name comes
// first so a packaged shell wins over a developer build left in the same
// directory.
inline std::vector<std::wstring> shell_executable_names() {
  return {L"msime-client-settings.exe", L"MSIME Client Preview.exe"};
}
// Locate the shell: an explicit override first, then the package layout. Only
// an existing file is accepted, so a stale setting cannot launch something
// else, and an empty answer keeps the menu rows visibly disabled.
inline std::optional<std::filesystem::path>
shell_executable(const std::filesystem::path &directory,
                 const std::wstring &configured) {
  std::error_code error;
  if (!configured.empty()) {
    const std::filesystem::path path(configured);
    if (!path.is_absolute() || !std::filesystem::is_regular_file(path, error))
      return std::nullopt;
    return path;
  }
  if (directory.empty() || !directory.is_absolute())
    return std::nullopt;
  for (const auto &name : shell_executable_names()) {
    const auto path = directory / name;
    if (std::filesystem::is_regular_file(path, error))
      return path;
  }
  return std::nullopt;
}
// Compose the child environment from this process's block plus the request.
// Existing MSIME_CLIENT_PANEL/MSIME_CLIENT_SETTINGS_PAGE entries are dropped,
// so a value this process was started with cannot outvote the clicked row.
// The result is the double-NUL terminated block CreateProcessW expects.
inline std::wstring shell_environment_block(const wchar_t *existing,
                                            const ShellSurfaceRequest &request) {
  static constexpr std::wstring_view panel_name = L"MSIME_CLIENT_PANEL=";
  static constexpr std::wstring_view page_name = L"MSIME_CLIENT_SETTINGS_PAGE=";
  auto owned = [](std::wstring_view entry) {
    auto starts_with = [entry](std::wstring_view name) {
      if (entry.size() < name.size())
        return false;
      for (size_t i = 0; i < name.size(); ++i)
        if (towupper(entry[i]) != towupper(name[i]))
          return false;
      return true;
    };
    return starts_with(panel_name) || starts_with(page_name);
  };
  std::wstring block;
  for (const wchar_t *entry = existing; entry && *entry;) {
    const std::wstring_view value(entry);
    // A leading '=' names a drive's current directory, which the child needs.
    if (!owned(value)) {
      block.append(value);
      block.push_back(L'\0');
    }
    entry += value.size() + 1;
  }
  auto append = [&block](std::wstring_view name, const std::string &value) {
    if (value.empty())
      return;
    block.append(name);
    // The contract only carries short lowercase ASCII identifiers; nothing a
    // caller could turn into another variable or a command line.
    if (value.size() > 32)
      throw std::invalid_argument("Invalid shell surface request");
    for (unsigned char c : value) {
      if (!((c >= 'a' && c <= 'z') || c == '-'))
        throw std::invalid_argument("Invalid shell surface request");
      block.push_back(static_cast<wchar_t>(c));
    }
    block.push_back(L'\0');
  };
  append(panel_name, request.panel);
  append(page_name, request.page);
  block.push_back(L'\0');
  return block;
}
} // namespace msime::windows

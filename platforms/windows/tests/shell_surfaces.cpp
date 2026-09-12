#include "ShellSurfaces.h"
#include <chrono>
#include <cstdio>
#include <fstream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Shell surface test failed at line " +
                             std::to_string(line));
}
#define require(...) require_at((__VA_ARGS__), __LINE__)
namespace {
// The block is double-NUL terminated, so entries are compared one at a time.
std::vector<std::wstring> entries(const std::wstring &block) {
  std::vector<std::wstring> result;
  for (size_t start = 0; start < block.size() && block[start];) {
    const auto end = block.find(L'\0', start);
    result.emplace_back(block, start, end - start);
    start = end + 1;
  }
  return result;
}
bool contains(const std::vector<std::wstring> &values, const std::wstring &entry) {
  for (const auto &value : values)
    if (value == entry)
      return true;
  return false;
}
} // namespace
int main() {
  try {
    // Every surface the menu offers reaches the shell, and only the toolbar
    // row - which this process owns - stays out of the contract.
    require(shell_surface_request(TrayMenuCommand::OpenEmojiPanel)->panel ==
            "emoji");
    require(shell_surface_request(TrayMenuCommand::OpenHandwritingPanel)
                ->panel == "handwriting");
    require(shell_surface_request(TrayMenuCommand::OpenKeyboardPanel)->panel ==
            "keyboard");
    require(shell_surface_request(TrayMenuCommand::ToggleVoiceInput)->panel ==
            "voice");
    const auto settings = shell_surface_request(TrayMenuCommand::OpenSettings);
    require(settings && settings->panel.empty() && settings->page.empty());
    const auto about = shell_surface_request(TrayMenuCommand::OpenAbout);
    require(about && about->panel.empty() && about->page == "about");
    require(!shell_surface_request(TrayMenuCommand::ToggleFloatingToolbar));

    // A panel request replaces whatever this process inherited and leaves the
    // rest of the environment, including drive current directories, alone.
    const std::wstring existing =
        std::wstring(L"PATH=C:\\Windows") + L'\0' +
        L"msime_client_panel=stale" + L'\0' + L"MSIME_CLIENT_SETTINGS_PAGE=old" +
        L'\0' + L"=C:=C:\\work" + L'\0';
    const auto panel = entries(shell_environment_block(
        existing.c_str(), *shell_surface_request(TrayMenuCommand::OpenEmojiPanel)));
    require(contains(panel, L"PATH=C:\\Windows"));
    require(contains(panel, L"=C:=C:\\work"));
    require(contains(panel, L"MSIME_CLIENT_PANEL=emoji"));
    for (const auto &entry : panel)
      require(entry != L"msime_client_panel=stale" &&
              entry != L"MSIME_CLIENT_SETTINGS_PAGE=old");

    // The settings row asks for no panel at all, so the shell opens its own
    // window; the about row names a section instead.
    const auto plain = entries(shell_environment_block(existing.c_str(), *settings));
    require(plain.size() == 2 && contains(plain, L"PATH=C:\\Windows"));
    const auto about_block = entries(shell_environment_block(existing.c_str(), *about));
    require(contains(about_block, L"MSIME_CLIENT_SETTINGS_PAGE=about"));
    for (const auto &entry : about_block)
      require(entry.rfind(L"MSIME_CLIENT_PANEL=", 0) != 0);

    // Nothing but a short lowercase identifier may reach the child.
    for (const char *invalid : {"emoji panel", "Emoji", "emoji=1", "../etc"}) {
      bool rejected = false;
      try {
        (void)shell_environment_block(L"\0", ShellSurfaceRequest{invalid, {}});
      } catch (const std::invalid_argument &) {
        rejected = true;
      }
      require(rejected);
    }

    // Discovery accepts only an existing file, and the packaged name wins over
    // a developer build sitting in the same directory.
    const auto root =
        std::filesystem::temp_directory_path() /
        ("msime-shell-fixture-" +
         std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(root);
    require(!shell_executable(root, {}));
    require(!shell_executable("relative", {}));
    std::ofstream(root / "MSIME Client Preview.exe") << "fixture";
    require(shell_executable(root, {}) == root / "MSIME Client Preview.exe");
    std::ofstream(root / "msime-client-settings.exe") << "fixture";
    require(shell_executable(root, {}) == root / "msime-client-settings.exe");
    const auto configured = root / "elsewhere.exe";
    require(!shell_executable(root, configured.wstring()));
    std::ofstream(configured) << "fixture";
    require(shell_executable(root, configured.wstring()) == configured);
    require(!shell_executable(root, L"msime-client-settings.exe"));
    std::error_code error;
    std::filesystem::remove_all(root, error);
  } catch (const std::exception &error) {
    std::fputs(error.what(), stderr);
    std::fputs("\n", stderr);
    return 1;
  }
  return 0;
}

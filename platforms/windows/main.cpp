#include "PreviewConfig.h"
#include "TrayMenuWindow.h"
#include "CandidateSkin.h"
#include "CandidateWindow.h"
#include "ModeWindow.h"
#include "FloatingToolbarWindow.h"
#include "PreviewDispatcher.h"
#include "ShellLauncher.h"
#include "StateRootLease.h"
#include "WindowsServer.h"
#include "ClipboardHistory.h"
#include "ipc_negotiation.h"
#include <fstream>
#include <iostream>
#include <memory>

namespace {
// The desktop shell is packaged beside this Server; a development build points
// at another copy with the same variable the Linux host reads.
std::filesystem::path executable_directory() {
  std::vector<wchar_t> path(32768);
  const DWORD length =
      GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length == path.size())
    return {};
  return std::filesystem::path(std::wstring(path.data(), length)).parent_path();
}
std::wstring configured_shell_command() {
  std::vector<wchar_t> value(32768);
  const DWORD length = GetEnvironmentVariableW(
      L"MSIME_CLIENT_SETTINGS_COMMAND", value.data(),
      static_cast<DWORD>(value.size()));
  return length && length < value.size() ? std::wstring(value.data(), length)
                                         : std::wstring{};
}
// Resolve the configured skin through the shared catalog. Appearance is not
// worth failing a running Server over, so an unreadable root or an unknown
// package leaves the built-in theme in place.
msime::windows::CandidatePalette
resolve_palette(const msime::windows::PreviewConfig &config) {
  const bool dark = config.dark_theme;
  auto builtin = dark ? msime::windows::CandidatePalette{}
                      : msime::windows::candidate_light_palette();
  if (config.skin_directory.empty() || config.skin_id.empty())
    return builtin;
  try {
    const auto root = config.skin_directory.u8string();
    std::unique_ptr<char, decltype(&msime_client_string_free)> owned(
        msime_client_skin_catalog(
            reinterpret_cast<const uint8_t *>(root.data()), root.size()),
        msime_client_string_free);
    if (!owned)
      return builtin;
    const auto document = nlohmann::json::parse(owned.get(), nullptr, false);
    if (document.is_discarded() || !document.value("ok", false))
      return builtin;
    // Compatibility is checked against the layout actually being rendered.
    return msime::windows::candidate_skin_palette(
        document.at("value"), config.skin_id, dark,
        config.horizontal_candidates ? "horizontal" : "vertical");
  } catch (const std::exception &) {
    return builtin;
  }
}
std::atomic<bool> stopping{false};
static_assert(std::atomic<bool>::is_always_lock_free);
BOOL WINAPI console_control(DWORD event) {
  if (event != CTRL_C_EVENT && event != CTRL_BREAK_EVENT)
    return FALSE;
  stopping.store(true);
  return TRUE;
}
struct ConsoleControl {
  ConsoleControl() {
    if (!SetConsoleCtrlHandler(console_control, TRUE))
      throw std::runtime_error("Console control unavailable");
  }
  ~ConsoleControl() { SetConsoleCtrlHandler(console_control, FALSE); }
};
bool contains(const std::filesystem::path &parent,
              const std::filesystem::path &child) {
  auto p = parent.begin(), c = child.begin();
  for (; p != parent.end(); ++p, ++c)
    if (c == child.end() || CompareStringOrdinal(p->c_str(), -1, c->c_str(), -1,
                                                 TRUE) != CSTR_EQUAL)
      return false;
  return true;
}
} // namespace
int wmain(int argc, wchar_t **argv) {
  using namespace msime::windows;
  if (argc == 2 && std::wstring(argv[1]) == L"--help") {
    std::cout << "MSIME Client preview Server: --config <absolute-json-path>\n"
                 "No TSF registration or production pipe names. Ctrl+C stops.\n"
                 "Unsupported routes (including unobserved Enter) disconnect; "
                 "not a complete IME.\n";
    return 0;
  }
  if (argc != 3 || std::wstring(argv[1]) != L"--config")
    return 2;
  try {
    const std::filesystem::path config_path(argv[2]);
    if (!config_path.is_absolute())
      throw std::invalid_argument("Relative config path");
    std::ifstream input(config_path, std::ios::binary);
    if (!input)
      throw std::runtime_error("Configuration unavailable");
    std::string document(16385, '\0');
    input.read(document.data(), static_cast<std::streamsize>(document.size()));
    if (input.bad())
      throw std::runtime_error("Configuration read failed");
    document.resize(static_cast<size_t>(input.gcount()));
    auto config = PreviewConfig::parse(document);
    config.resources = std::filesystem::canonical(config.resources);
    config.state_root = std::filesystem::weakly_canonical(config.state_root);
    if (contains(config.resources, config.state_root) ||
        contains(config.state_root, config.resources))
      throw std::invalid_argument("Resources and state must be disjoint");
    StateRootLease lease(config.state_root);
    ConsoleControl console;
    const auto bootstrap =
        nlohmann::json{{"resources", config.resources.u8string()},
                       {"state_root", config.state_root.u8string()}}
            .dump();
    std::unique_ptr<char, decltype(&msime_client_string_free)> response(
        msime_client_prepare_host(
            reinterpret_cast<const uint8_t *>(bootstrap.data()),
            bootstrap.size()),
        msime_client_string_free);
    if (!response)
      throw std::runtime_error("Host preparation failed");
    const auto prepared = nlohmann::json::parse(response.get());
    if (!prepared.at("ok").get<bool>())
      throw std::runtime_error("Host preparation failed");
    if (stopping.load())
      return 0;
    // Keep the native listener on the same file used by the shared desktop
    // shell; this is the cross-process handoff for the clipboard panel.
    ClipboardHistory clipboard_history(config.state_root / "clipboard_history.json");
    WindowsServerOptions options;
    options.pipes.names = config.pipe_names();
    options.pipes.capabilities = FanyImeProtocol::RequiredCapabilities;
    options.preferences_directory = config.state_root.u8string();
    options.preferences_published =
        [&](const PreferenceSnapshot &snapshot) {
          const auto preferences =
              nlohmann::json::parse(snapshot.serialized()).at("preferences");
          clipboard_history.set_enabled(
              preferences.value("clipboard_history", false));
        };
    WindowsServer server(
        options, prepared.at("value").dump(), preview_key_handler(config),
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    ClipboardMonitor clipboard_monitor(
        clipboard_history, [](std::string) {});
    if (!clipboard_monitor.start())
      throw std::runtime_error("Clipboard monitor unavailable");
    CandidateClickWorker clicks([&](const CandidateClick &click) {
      if (server.request_selection(click.lease, click.session, click.generation,
                                   click.index) ==
          SelectionRequestResult::Failed)
        throw std::runtime_error("Candidate selection failed");
    });
    ModeClickWorker mode_clicks([&](const ModeClick &click) {
      if (server.request_mode(click.lease, click.mode) == ModeRequestResult::WriteFailed)
        throw std::runtime_error("Mode request failed");
    });
    struct ClickShutdown {
      WindowsServer &server;
      CandidateClickWorker &clicks;
      ModeClickWorker &modes;
      ~ClickShutdown() {
        clicks.request_stop();
        modes.request_stop();
        server.request_stop();
        clicks.stop();
        modes.stop();
      }
    } click_shutdown{server, clicks, mode_clicks};
    CandidateWindow candidates(
        [&] { return server.candidate_view(); },
        [&](const CandidateClick &click) { (void)clicks.submit(click); }, 16, 16,
        std::nullopt, "Segoe UI", {}, config.dark_theme,
        config.horizontal_candidates);
    const auto palette = resolve_palette(config);
    candidates.set_palette(palette);
    ModeWindow modes([&] { return server.mode_view(); },
                     [&](const ModeClick &click) { (void)mode_clicks.submit(click); });
    modes.set_palette(palette);
    FloatingToolbarWindow toolbar(
        [&] { return server.mode_view(); },
        [&](const ModeClick &click) { (void)mode_clicks.submit(click); });
    toolbar.set_palette(palette);
    // The Server owns the floating toolbar. Every other row opens a surface in
    // the shared desktop shell, which is a separate process: with no shell
    // installed beside this Server those rows stay visible and disabled rather
    // than accepting a click that does nothing.
    bool toolbar_visible = config.floating_toolbar_enabled;
    const auto shell = shell_executable(executable_directory(),
                                        configured_shell_command());
    toolbar.set_settings_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::Settings);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_emoji_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenEmojiPanel);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_handwriting_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenHandwritingPanel);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_keyboard_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenKeyboardPanel);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_voice_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::ToggleVoiceInput);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_about_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenAbout);
      if (shell && request) (void)launch_shell_surface(*shell, *request);
    });
    toolbar.set_hide_action([&] { toolbar.hide(); });
    TrayMenuCapabilities menu_capabilities;
    menu_capabilities.emoji_panel = shell.has_value();
    menu_capabilities.handwriting_panel = shell.has_value();
    menu_capabilities.keyboard_panel = shell.has_value();
    menu_capabilities.voice_input = shell.has_value();
    menu_capabilities.settings = shell.has_value();
    TrayMenuWindow tray(
        menu_capabilities,
        [&](TrayMenuCommand command) {
          if (command == TrayMenuCommand::ToggleFloatingToolbar) {
            toolbar_visible = !toolbar_visible;
            if (!toolbar_visible)
              toolbar.hide();
            return true;
          }
          const auto request = shell_surface_request(command);
          // Report only what was observed: a row that could not start the
          // shell stays unhandled, so the menu does not close on a promise.
          return shell && request && launch_shell_surface(*shell, *request);
        },
        [&] { return toolbar_visible; });
    tray.set_palette(palette);
    std::cout
        << "Preview Server running; candidate selection and mode controls enabled.\n";
    while (!stopping.load() && server.failure() == ControllerFailure::None &&
           !candidates.failed() && !clicks.failed() &&
           !modes.failed() && !mode_clicks.failed() && !toolbar.failed() &&
           !tray.failed()) {
      MSG message{};
      // Bound each batch so a message flood cannot starve stop/focus polling.
      for (size_t i = 0;
           i < 64 && PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE); ++i) {
        if (message.message == WM_QUIT) {
          stopping.store(true);
          break;
        }
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
      if (stopping.load())
        break;
      candidates.refresh();
      modes.refresh();
      toolbar.refresh(toolbar_visible);
      if (MsgWaitForMultipleObjectsEx(0, nullptr, 50, QS_ALLINPUT,
                                      MWMO_INPUTAVAILABLE) == WAIT_FAILED)
        throw std::runtime_error("Candidate message wait failed");
    }
    candidates.hide();
    modes.hide();
    toolbar.hide();
    tray.hide();
    clicks.request_stop();
    mode_clicks.request_stop();
    server.stop();
    clicks.stop();
    mode_clicks.stop();
    return server.failure() == ControllerFailure::None &&
                   !candidates.failed() && !clicks.failed() &&
                   !modes.failed() && !mode_clicks.failed()
               ? 0
               : 1;
  } catch (...) {
    std::cerr << "Preview Server failed; verify configuration, resources, "
                 "state ownership and pipe availability.\n";
    return 1;
  }
}

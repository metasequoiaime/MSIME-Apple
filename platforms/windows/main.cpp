#include "CandidateAppearance.h"
#include "PreviewConfig.h"
#include "TrayMenuWindow.h"
#include "CandidateSkin.h"
#include "CandidateWindow.h"
#include "ModeWindow.h"
#include "FloatingToolbarWindow.h"
#include "PreviewDispatcher.h"
#include "ProductionDispatcher.h"
#include "ShellLauncher.h"
#include "StateRootLease.h"
#include "WatchdogPolicy.h"
#include "WindowsServer.h"
#include "VoiceInputSession.h"
#include "VoiceHotkey.h"
#include "SystemAudioMuter.h"
#include "ClipboardHistory.h"
#include "AuxListener.h"
#include "ServerLaunch.h"
#include "TrayMenuDispatch.h"
#include "ipc_negotiation.h"
#include "../../vendor/MSIME-Engine/contracts/windows_ipc.h"
#include <fstream>
#include <iostream>
#include <memory>
#include <mutex>
#ifdef _WIN32
#include <shlobj.h>
#endif

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
std::wstring voice_audio_path(const msime::windows::PreviewConfig &config,
                              const wchar_t *filename) {
  const auto executable = executable_directory();
  const std::array<std::filesystem::path, 5> candidates = {
      config.state_root / "audios" / filename,
      config.resources / "audios" / filename,
      config.resources / "assets" / "audios" / filename,
      executable / "assets" / "audios" / filename,
      executable.parent_path() / "share" / "msime" / "audios" / filename};
  std::error_code error;
  for (const auto &candidate : candidates)
    if (std::filesystem::is_regular_file(candidate, error))
      return candidate.wstring();
  return {};
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
  auto builtin = msime::windows::candidate_builtin_palette(config.skin_id, dark);
  if (config.skin_directory.empty() || config.skin_id.empty())
    return builtin;
  // The shipped skins are resolved from the table above, never from disk - the
  // shared catalog refuses to load a package under one of their names, so
  // asking it would only ever come back empty and fall through to fluent.
  if (msime::windows::candidate_builtin_skin(config.skin_id))
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
std::atomic<bool> restart_requested{false};
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
std::filesystem::path production_state_directory() {
#ifdef _WIN32
  PWSTR app_data = nullptr;
  if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                  &app_data)))
    return {};
  const std::filesystem::path state =
      std::filesystem::path(app_data) / L"MSIME-Client";
  CoTaskMemFree(app_data);
  return state;
#else
  return {};
#endif
}
std::string read_document(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary);
  if (!input)
    throw std::runtime_error("Configuration unavailable");
  std::string document(16385, '\0');
  input.read(document.data(), static_cast<std::streamsize>(document.size()));
  if (input.bad() || input.gcount() > 16384)
    throw std::runtime_error("Configuration read failed");
  document.resize(static_cast<size_t>(input.gcount()));
  return document;
}
// The native toolbar's character-set button uses the same revisioned store as
// the settings shell. Read and write on its single action worker so the UI
// thread never waits on the preferences lock.
bool toggle_traditional_output(const std::filesystem::path &directory,
                               std::atomic<bool> &state) {
  try {
    const auto root = directory.u8string();
    std::unique_ptr<char, decltype(&msime_client_string_free)> loaded(
        msime_client_load_preferences(
            reinterpret_cast<const uint8_t *>(root.data()), root.size()),
        msime_client_string_free);
    if (!loaded)
      return false;
    const auto response = nlohmann::json::parse(loaded.get());
    if (!response.value("ok", false) || !response.at("value").is_object())
      return false;
    auto snapshot = response.at("value");
    const auto revision = snapshot.at("revision").get<uint64_t>();
    auto &preferences = snapshot.at("preferences");
    const bool enabled = preferences.value("traditional_chinese_output", false);
    preferences["traditional_chinese_output"] = !enabled;
    const auto serialized = snapshot.dump();
    std::unique_ptr<char, decltype(&msime_client_string_free)> saved(
        msime_client_save_preferences(
            reinterpret_cast<const uint8_t *>(root.data()), root.size(),
            revision,
            reinterpret_cast<const uint8_t *>(serialized.data()),
            serialized.size()),
        msime_client_string_free);
    if (!saved)
      return false;
    const auto saved_response = nlohmann::json::parse(saved.get());
    if (!saved_response.value("ok", false) ||
        !saved_response.at("value").is_object())
      return false;
    state.store(!enabled, std::memory_order_release);
    return true;
  } catch (...) {
    return false;
  }
}
// Read the stored preferences block, or nothing if it cannot be read. The
// shipped card has usable built-in defaults, so an unreadable store degrades
// to those rather than stopping the IME from starting.
std::optional<nlohmann::json>
load_preference_block(const std::filesystem::path &directory) {
  try {
    const auto root = directory.u8string();
    std::unique_ptr<char, decltype(&msime_client_string_free)> loaded(
        msime_client_load_preferences(
            reinterpret_cast<const uint8_t *>(root.data()), root.size()),
        msime_client_string_free);
    if (!loaded)
      return std::nullopt;
    const auto response = nlohmann::json::parse(loaded.get());
    if (!response.value("ok", false) || !response.at("value").is_object())
      return std::nullopt;
    const auto &snapshot = response.at("value");
    if (!snapshot.contains("preferences") ||
        !snapshot.at("preferences").is_object())
      return std::nullopt;
    return snapshot.at("preferences");
  } catch (...) {
    return std::nullopt;
  }
}
// "system" follows Windows. Absent or unreadable, keep the shipped dark card
// rather than guessing light and flashing a white panel over a dark desktop.
bool system_prefers_dark() {
  DWORD light = 0;
  DWORD size = sizeof(light);
  if (RegGetValueW(HKEY_CURRENT_USER,
                   L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\"
                   L"Personalize",
                   L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light,
                   &size) != ERROR_SUCCESS)
    return true;
  return light == 0;
}
std::string production_preview_document(const std::string &runtime_document,
                                        const std::filesystem::path &fallback) {
  const auto host = nlohmann::json::parse(runtime_document);
  if (!host.is_object() || !host.at("resources").is_string())
    throw std::invalid_argument("Invalid production host options");
  const auto state = host.value("preferences_directory", fallback.u8string());
  if (state.empty())
    throw std::invalid_argument("Production state directory unavailable");
  nlohmann::json document{
      {"format_version", 1},
      {"resources", host.at("resources")},
      {"state_root", state},
      {"pipe_namespace", "production"},
      {"preedit_style", "local"},
  };
  const auto preferences = load_preference_block(std::filesystem::u8path(state));
  if (!preferences)
    return document.dump();
  document["preedit_style"] =
      msime::windows::tsf_preedit_style(*preferences);
  document["appearance"] = msime::windows::candidate_appearance(
      std::filesystem::u8path(state), *preferences, system_prefers_dark());
  msime::windows::apply_floating_toolbar(document, *preferences);
  // Last line of defence. The field filtering above is deliberately
  // conservative, but a preference shape nobody anticipated must still not
  // cost the user their IME: if the assembled document would not load, drop
  // the appearance and start with the built-in card.
  try {
    msime::windows::PreviewConfig::parse(document.dump());
  } catch (...) {
    document.erase("appearance");
    document.erase("floating_toolbar_enabled");
    document.erase("floating_toolbar_scale");
    document.erase("floating_toolbar_font_size");
    document.erase("floating_toolbar_items");
    document["preedit_style"] = "local";
  }
  return document.dump();
}
class ProductionInstance final {
public:
  ProductionInstance() {
    handle_ = CreateMutexW(nullptr, FALSE,
                           L"Local\\MetasequoiaImeServer_SingleInstance");
    if (!handle_)
      throw std::runtime_error("Server instance guard unavailable");
    already_running_ = GetLastError() == ERROR_ALREADY_EXISTS;
  }
  ~ProductionInstance() {
    if (handle_)
      CloseHandle(handle_);
  }
  bool already_running() const { return already_running_; }
private:
  HANDLE handle_ = nullptr;
  bool already_running_ = false;
};
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
  const auto launch = parse_server_arguments(argc, argv);
  const bool production = launch.kind == ServerLaunchKind::Managed;
  if (launch.kind == ServerLaunchKind::Invalid)
    return 2;
  try {
    const auto default_state = production_state_directory();
    const std::filesystem::path config_path =
        production ? default_state / L"runtime-options.json"
                    : std::filesystem::path(launch.config);
    if (!config_path.is_absolute())
      throw std::invalid_argument("Relative config path");
    auto document = read_document(config_path);
    if (production)
      document = production_preview_document(document, default_state);
    auto config = PreviewConfig::parse(document);
    config.resources = std::filesystem::canonical(config.resources);
    config.state_root = std::filesystem::weakly_canonical(config.state_root);
    if (contains(config.resources, config.state_root) ||
        contains(config.state_root, config.resources))
      throw std::invalid_argument("Resources and state must be disjoint");
    std::unique_ptr<ProductionInstance> instance;
    if (production) {
      instance = std::make_unique<ProductionInstance>();
      if (instance->already_running())
        return 0;
    }
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
    auto traditional_output = std::make_shared<std::atomic<bool>>(
        prepared.at("value").at("preferences")
            .value("traditional_chinese_output", false));
    // Keep the native listener on the same file used by the shared desktop
    // shell; this is the cross-process handoff for the clipboard panel.
    ClipboardHistory clipboard_history(config.state_root / "clipboard_history.json");
    clipboard_history.set_enabled(
        prepared.at("value").at("preferences").value("clipboard_history", false));
    auto voice_config = std::make_shared<VoiceInputConfig>();
    auto voice_config_mutex = std::make_shared<std::mutex>();
    WindowsServerOptions options;
    options.pipes.names = production
                              ? std::array<std::wstring, 3>{
                                    FANY_IME_NAMED_PIPE,
                                    FANY_IME_TO_TSF_NAMED_PIPE,
                                    FANY_IME_TO_TSF_WORKER_THREAD_NAMED_PIPE}
                              : config.pipe_names();
    options.pipes.capabilities = FanyImeProtocol::RequiredCapabilities;
    options.preferences_directory = config.state_root.u8string();
    options.preferences_published =
        [&, voice_config, voice_config_mutex, traditional_output](
            const PreferenceSnapshot &snapshot) {
          const auto preferences =
              nlohmann::json::parse(snapshot.serialized()).at("preferences");
          traditional_output->store(
              preferences.value("traditional_chinese_output", false),
              std::memory_order_release);
          clipboard_history.set_enabled(
              preferences.value("clipboard_history", false));
          const auto input = preferences.value("voice_input", nlohmann::json::object());
          VoiceInputConfig next;
          next.enabled = input.value("enabled", true);
          next.start_sound = input.value("start_sound", true);
          next.end_sound = input.value("end_sound", true);
          next.sound_enabled = input.value("sound_enabled", true);
          next.mute_system_audio = input.value("mute_system_audio", false);
          next.hotkey_ralt = input.value("hotkey_ralt", true);
          next.hotkey_ctrl_f9 = input.value("hotkey_ctrl_f9", true);
          next.hotkey_ctrl_win = input.value("hotkey_ctrl_win", false);
          next.hotkey_rctrl_ralt = input.value("hotkey_rctrl_ralt", false);
          next.hotkey_hold_space_lock = input.value("hotkey_hold_space_lock", true);
          next.stream_inline_preedit = input.value("stream_inline_preedit", true);
          next.commit_mode = input.value("commit_mode", std::string{"tsf"});
          next.asr_provider = input.value("asr_provider", std::string{"doubao"});
          next.endpoint = input.value("asr_endpoint", std::string{});
          next.model = input.value("asr_model", std::string{});
          next.token = input.value("asr_token", std::string{});
          next.app_key = input.value("asr_app_key", std::string{});
          next.resource_id = input.value("asr_resource_id", std::string{});
          next.enable_itn = input.value("doubao_enable_itn", true);
          next.enable_punc = input.value("doubao_enable_punc", true);
          next.enable_ddc = input.value("doubao_enable_ddc", false);
          next.boosting_table_id = input.value("doubao_boosting_table_id", std::string{});
          next.language = input.value("language", std::string{"zh-cn"});
          next.polish_enabled = input.value("polish_enabled", false);
          next.polish_text = input.value("polish_text", false);
          next.polish_provider = input.value("polish_provider", std::string{});
          next.polish_token = input.value("polish_token", std::string{});
          next.polish_endpoint = input.value("polish_endpoint", std::string{});
          next.polish_model = input.value("polish_model", std::string{});
          next.polish_prompt_id = input.value("polish_prompt_id", std::string{"cleanup"});
          next.polish_prompt = input.value("polish_prompt", std::string{});
          next.polish_prompt_custom_1 = input.value("polish_prompt_custom_1", std::string{});
          next.polish_prompt_custom_2 = input.value("polish_prompt_custom_2", std::string{});
          next.polish_prompt_custom_3 = input.value("polish_prompt_custom_3", std::string{});
          std::lock_guard lock(*voice_config_mutex);
          *voice_config = std::move(next);
        };
    WindowsServer server(
        options, prepared.at("value").dump(),
        production ? production_key_handler() : preview_key_handler(config),
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    WaveOverlay voice_overlay;
    VoiceInputSession *voice_session = nullptr;
    if (!voice_overlay.init(
            GetModuleHandleW(nullptr), [&voice_session](WaveOverlay::Action action) {
              if (!voice_session)
                return;
              if (action == WaveOverlay::Action::Cancel)
                voice_session->cancel();
              else if (voice_session->recording())
                voice_session->stop();
            }))
      throw std::runtime_error("Voice overlay unavailable");
    auto voice = std::make_unique<VoiceInputSession>(
        voice_overlay,
        [&] {
          const auto view = server.mode_view();
          return view ? std::optional<FocusLease>(view->lease) : std::nullopt;
        },
        [&](const FocusLease &lease, uint32_t message, std::wstring_view text,
            wchar_t generation) {
          return server.send_voice_composition(lease, message, text, generation);
        },
        [voice_config, voice_config_mutex] {
          std::lock_guard lock(*voice_config_mutex);
          return *voice_config;
        });
    voice_session = voice.get();
    configure_audio_mute_state_path(
        (config.state_root / "voice_system_audio_mute_state.txt").wstring());
    (void)voice->init_cues(voice_audio_path(config, L"start.mp3"),
                           voice_audio_path(config, L"end.mp3"));
    VoiceHotkeyController voice_hotkeys(
        *voice,
        [voice_config, voice_config_mutex] {
          std::lock_guard lock(*voice_config_mutex);
          return *voice_config;
        },
        [&] { return server.mode_view().has_value(); });
    ClipboardMonitor clipboard_monitor(
        clipboard_history, [](std::string) {});
    // Clipboard history is an optional convenience, so a monitor that cannot
    // start leaves it inert rather than taking the IME down with it. Failing
    // here used to cost the user all text input because a message-only window
    // or a class registration failed.
    if (!clipboard_monitor.start())
      std::cerr << "Clipboard history unavailable; continuing without it\n";
    CandidateClickWorker clicks([&](const CandidateClick &click) {
      if (click.action == CandidateAction::Select) {
        if (server.request_selection(click.lease, click.session,
                                     click.generation, click.index) ==
            SelectionRequestResult::Failed)
          throw std::runtime_error("Candidate selection failed");
        return;
      }
      if (server.request_candidate_action(
              click.lease, click.session, click.generation, click.index,
              click.action, click.position) ==
          CandidateActionRequestResult::Failed)
          throw std::runtime_error("Candidate action failed");
    });
    CandidatePageWorker pages([&](const CandidatePage &page) {
      if (server.request_page(page) == CandidatePageRequestResult::Failed)
        throw std::runtime_error("Candidate paging failed");
    });
    ModeClickWorker mode_clicks([&](const ModeClick &click) {
      if (server.request_mode(click.lease, click.mode) == ModeRequestResult::WriteFailed)
        throw std::runtime_error("Mode request failed");
    });
    CharacterSetClickWorker character_set_clicks(
        [traditional_output, directory = config.state_root](
            const CharacterSetClick &) {
          (void)toggle_traditional_output(directory, *traditional_output);
        });
    struct ClickShutdown {
      WindowsServer &server;
      CandidateClickWorker &clicks;
      CandidatePageWorker &pages;
      ModeClickWorker &modes;
      CharacterSetClickWorker &character_sets;
      ~ClickShutdown() {
        clicks.request_stop();
        pages.request_stop();
        modes.request_stop();
        character_sets.request_stop();
        server.request_stop();
        clicks.stop();
        pages.stop();
        modes.stop();
        character_sets.stop();
      }
    } click_shutdown{server, clicks, pages, mode_clicks, character_set_clicks};
    std::optional<COLORREF> candidate_text_color;
    if (!config.candidate_text_color.empty() && config.candidate_text_color != "auto" &&
        config.candidate_text_color != "none") {
      const auto color = parse_css_color(config.candidate_text_color, {});
      candidate_text_color = RGB(static_cast<BYTE>(color.r * 255.0f),
                                 static_cast<BYTE>(color.g * 255.0f),
                                 static_cast<BYTE>(color.b * 255.0f));
    }
    CandidateWindow candidates(
        [&] { return server.candidate_view(); },
        [&](const CandidateClick &click) { (void)clicks.submit(click); },
        static_cast<unsigned>(config.candidate_font_size),
        static_cast<unsigned>(config.candidate_preedit_font_size), candidate_text_color,
        config.candidate_font, config.candidate_fallback_fonts, config.dark_theme,
        config.horizontal_candidates, config.candidate_show_preedit,
        [&](const CandidatePage &page) { (void)pages.submit(page); });
    const auto palette = resolve_palette(config);
    auto resolved_palette = palette;
    if (!config.candidate_number_color.empty() && config.candidate_number_color != "auto" &&
        config.candidate_number_color != "none")
      resolved_palette.number = parse_css_color(config.candidate_number_color, resolved_palette.number);
    if (!config.candidate_surface_color.empty() && config.candidate_surface_color != "auto" &&
        config.candidate_surface_color != "none")
      resolved_palette.surface = parse_css_color(config.candidate_surface_color, resolved_palette.surface);
    if (!config.candidate_border_color.empty() && config.candidate_border_color != "auto" &&
        config.candidate_border_color != "none")
      resolved_palette.border = parse_css_color(config.candidate_border_color, resolved_palette.border);
    if (!config.candidate_selected_color.empty() && config.candidate_selected_color != "auto" &&
        config.candidate_selected_color != "none")
      resolved_palette.selected = parse_css_color(config.candidate_selected_color, resolved_palette.selected);
    if (!config.candidate_hover_color.empty() && config.candidate_hover_color != "auto" &&
        config.candidate_hover_color != "none")
      resolved_palette.hover = parse_css_color(config.candidate_hover_color, resolved_palette.hover);
    if (!config.candidate_accent_color.empty() && config.candidate_accent_color != "auto" &&
        config.candidate_accent_color != "none")
      resolved_palette.accent = parse_css_color(config.candidate_accent_color, resolved_palette.accent);
    if (config.candidate_selected_bar)
      resolved_palette.show_selected_bar = *config.candidate_selected_bar;
    candidates.set_palette(resolved_palette);
    ModeWindow modes([&] { return server.mode_view(); },
                     [&](const ModeClick &click) { (void)mode_clicks.submit(click); });
    modes.set_palette(resolved_palette);
    bool toolbar_visible = config.floating_toolbar_enabled;
    FloatingToolbarWindow toolbar(
        [&] { return server.mode_view(); },
        [&](const ModeClick &click) { (void)mode_clicks.submit(click); });
    toolbar.set_palette(resolved_palette);
    toolbar.set_scale(config.floating_toolbar_scale);
    toolbar.set_font_size(config.floating_toolbar_font_size);
    toolbar.set_items(config.floating_toolbar_items);
    toolbar.set_character_set_reader([traditional_output] {
      return std::optional<bool>(
          traditional_output->load(std::memory_order_acquire));
    });
    // The Server owns the floating toolbar. Every other row opens a surface in
    // the shared desktop shell, which is a separate process: with no shell
    // installed beside this Server those rows stay visible and disabled rather
    // than accepting a click that does nothing.
    const auto shell = shell_executable(executable_directory(),
                                        configured_shell_command());
    const ShellLaunchContext shell_context{
        config.state_root, config.state_root / L"runtime-options.json"};
    const auto launch_shell = [&](const ShellSurfaceRequest &request) {
      return shell && launch_shell_surface(*shell, request, shell_context);
    };
    toolbar.set_character_set_action([&] {
      (void)character_set_clicks.submit(CharacterSetClick{});
    });
    toolbar.set_settings_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenSettings);
      if (request) (void)launch_shell(*request);
    });
    toolbar.set_emoji_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenEmojiPanel);
      if (request) (void)launch_shell(*request);
    });
    toolbar.set_handwriting_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenHandwritingPanel);
      if (request) (void)launch_shell(*request);
    });
    toolbar.set_keyboard_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenKeyboardPanel);
      if (request) (void)launch_shell(*request);
    });
    toolbar.set_voice_action([&] {
      (void)voice->toggle();
    });
    toolbar.set_about_action([&] {
      const auto request = shell_surface_request(TrayMenuCommand::OpenAbout);
      if (request) (void)launch_shell(*request);
    });
    toolbar.set_hide_action([&] {
      toolbar_visible = false;
      toolbar.hide();
    });
    TrayMenuCapabilities menu_capabilities;
    menu_capabilities.emoji_panel = shell.has_value();
    menu_capabilities.handwriting_panel = shell.has_value();
    menu_capabilities.keyboard_panel = shell.has_value();
    menu_capabilities.voice_input = true;
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
          if (command == TrayMenuCommand::ToggleVoiceInput)
            return voice->toggle();
          const auto request = shell_surface_request(command);
          // Report only what was observed: a row that could not start the
          // shell stays unhandled, so the menu does not close on a promise.
          return request && launch_shell(*request);
        },
        [&] { return toolbar_visible; });
    tray.set_palette(resolved_palette);
    // The language bar sends a right click over the Aux pipe; without a
    // listener the tray menu - and with it every shared-shell entry - is
    // unreachable. A failure here costs the menu, never the IME.
    TrayMenuMailbox tray_mailbox;
    DWORD aux_error = ERROR_SUCCESS;
    const std::wstring aux_name =
        production ? FANY_IME_AUX_NAMED_PIPE : config.aux_pipe_name();
    auto aux = AuxListener::create(
        aux_name,
        [&tray_mailbox](const TrayMenuAnchor &anchor) {
          tray_mailbox.publish(anchor);
        },
        aux_error,
        [](const std::wstring &message) {
          if (message == L"RestartServer") {
            restart_requested.store(true);
            stopping.store(true);
          }
        });
    if (!aux)
      std::cerr << "Tray menu unavailable: language bar endpoint not started\n";
    uint64_t tray_shown_at = 0;
    uint64_t pointer_left_at = 0;
    HWND tray_foreground = nullptr;
    std::cout
        << "Preview Server running; candidate selection and mode controls enabled.\n";
    while (!stopping.load() && server.failure() == ControllerFailure::None &&
           !candidates.failed() && !clicks.failed() && !pages.failed() &&
           !modes.failed() && !mode_clicks.failed() &&
           !character_set_clicks.failed() && !toolbar.failed()) {
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
      // The listener thread owns no window; the anchor is applied here, on the
      // thread that created the tray card.
      const uint64_t now = GetTickCount64();
      if (const auto anchor = tray_mailbox.take()) {
        switch (tray_menu_request_action(tray.visible(), now, tray_shown_at)) {
        case TrayMenuRequestAction::Show:
          if (tray.open(anchor->center_x, anchor->top)) {
            tray_shown_at = now;
            pointer_left_at = now;
            tray_foreground = GetForegroundWindow();
          }
          break;
        case TrayMenuRequestAction::Hide:
          tray.hide();
          break;
        case TrayMenuRequestAction::None:
          break;
        }
      }
      if (tray.visible()) {
        const bool inside = tray.pointer_inside();
        if (inside)
          pointer_left_at = now;
        const bool button_down =
            (GetAsyncKeyState(VK_LBUTTON) | GetAsyncKeyState(VK_RBUTTON)) &
            0x8000;
        if (tray_menu_dismissal(true, now, tray_shown_at, pointer_left_at,
                                inside, button_down != 0,
                                GetForegroundWindow() != tray_foreground))
          tray.hide();
      }
      if (MsgWaitForMultipleObjectsEx(0, nullptr, 50, QS_ALLINPUT,
                                      MWMO_INPUTAVAILABLE) == WAIT_FAILED)
        throw std::runtime_error("Candidate message wait failed");
    }
    candidates.hide();
    modes.hide();
    toolbar.hide();
    // Stop the listener and close the mailbox before the window goes away, so a
    // late anchor cannot reach a card that is being destroyed.
    if (aux)
      aux->stop();
    tray_mailbox.stop();
    tray.hide();
    clicks.request_stop();
    character_set_clicks.request_stop();
    mode_clicks.request_stop();
    server.stop();
    clicks.stop();
    character_set_clicks.stop();
    mode_clicks.stop();
    if (restart_requested.load())
      return msime::windows::watchdog::restart_exit_code;
    return server.failure() == ControllerFailure::None &&
                   !candidates.failed() && !clicks.failed() &&
                   !modes.failed() && !mode_clicks.failed() &&
                   !character_set_clicks.failed()
               ? 0
               : 1;
  } catch (...) {
    std::cerr << "Preview Server failed; verify configuration, resources, "
                 "state ownership and pipe availability.\n";
    return 1;
  }
}

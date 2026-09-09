#include "PreviewConfig.h"
#include "CandidateWindow.h"
#include "PreviewDispatcher.h"
#include "StateRootLease.h"
#include "WindowsServer.h"
#include "ipc_negotiation.h"
#include <fstream>
#include <iostream>

namespace {
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
    WindowsServerOptions options;
    options.pipes.names = config.pipe_names();
    options.pipes.capabilities = FanyImeProtocol::RequiredCapabilities;
    options.preferences_directory = config.state_root.u8string();
    WindowsServer server(
        options, prepared.at("value").dump(), preview_key_handler(config),
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    CandidateWindow candidates([&] { return server.candidate_view(); });
    std::cout
        << "Preview Server running; read-only native candidates enabled.\n";
    while (!stopping.load() && server.failure() == ControllerFailure::None &&
           !candidates.failed()) {
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
      if (MsgWaitForMultipleObjectsEx(0, nullptr, 50, QS_ALLINPUT,
                                      MWMO_INPUTAVAILABLE) == WAIT_FAILED)
        throw std::runtime_error("Candidate message wait failed");
    }
    candidates.hide();
    server.stop();
    return server.failure() == ControllerFailure::None && !candidates.failed()
               ? 0
               : 1;
  } catch (...) {
    std::cerr << "Preview Server failed; verify configuration, resources, "
                 "state ownership and pipe availability.\n";
    return 1;
  }
}

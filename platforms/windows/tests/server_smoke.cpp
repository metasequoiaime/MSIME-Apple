#include "WindowsServer.h"
#include "CandidateWindow.h"
#include "PreviewDispatcher.h"
#include "StateRootLease.h"
#include "TestHostOptions.h"
#include <cstring>
#include <filesystem>
#include <iostream>

using namespace msime::windows;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Native Windows server fixture failed");
}
template <class T> std::vector<uint8_t> fixture_bytes(const T &value) {
  std::vector<uint8_t> bytes(sizeof(T));
  std::memcpy(bytes.data(), &value, sizeof(T));
  return bytes;
}
struct ClientPipe {
  HANDLE handle = INVALID_HANDLE_VALUE;
  explicit ClientPipe(const std::wstring &name) {
    handle = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                         OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    require(handle != INVALID_HANDLE_VALUE);
    DWORD mode = PIPE_READMODE_MESSAGE;
    if (!SetNamedPipeHandleState(handle, &mode, nullptr, nullptr)) {
      CloseHandle(handle);
      handle = INVALID_HANDLE_VALUE;
      require(false);
    }
  }
  ~ClientPipe() {
    if (handle != INVALID_HANDLE_VALUE)
      CloseHandle(handle);
  }
  ClientPipe(const ClientPipe &) = delete;
  ClientPipe &operator=(const ClientPipe &) = delete;
};
} // namespace
int main() {
  try {
    {
      std::optional<CandidatePresentation> value;
      CandidateWindow window([&] { return value; });
      require(!IsWindowVisible(window.handle()));
      require((GetWindowLongPtrW(window.handle(), GWL_EXSTYLE) &
               WS_EX_NOACTIVATE) != 0);
      require(SendMessageW(window.handle(), WM_MOUSEACTIVATE, 0, 0) ==
              MA_NOACTIVATEANDEAT);
      CandidatePresentation frame{};
      frame.lease = {{42, {1, 2, 3}}, 1, 1};
      frame.session = 1;
      frame.generation = 1;
      frame.visible = true;
      frame.preedit = "U4e2d";
      frame.candidates.push_back({1, 1, 0, "中", true});
      value = frame;
      const auto foreground = GetForegroundWindow();
      window.refresh();
      UpdateWindow(window.handle());
      require(IsWindowVisible(window.handle()) && !window.failed());
      require(GetForegroundWindow() == foreground);
      window.refresh();
      require(!GetUpdateRect(window.handle(), nullptr, FALSE));
      value.reset();
      InvalidateRect(window.handle(), nullptr, FALSE);
      UpdateWindow(window.handle());
      require(!IsWindowVisible(window.handle())); // Paint rechecks the source.
      value = frame;
      value->visible = false;
      window.refresh();
      require(!IsWindowVisible(window.handle()));
      value = frame;
      value->preedit = std::string(1, static_cast<char>(0xff));
      window.refresh();
      UpdateWindow(window.handle());
      require(window.failed() && !IsWindowVisible(window.handle()));
    }
    const auto suffix = std::to_wstring(GetCurrentProcessId()) + L"-" +
                        std::to_wstring(GetTickCount64());
    const auto root = std::filesystem::temp_directory_path() /
                      (L"msime-server-fixture-" + suffix);
    require(std::filesystem::create_directory(root));
    struct Cleanup {
      std::filesystem::path path;
      ~Cleanup() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
      }
    } cleanup{root};
    {
      StateRootLease lease(root);
      bool rejected = false;
      try { StateRootLease second(root); } catch (...) { rejected = true; }
      require(rejected);
    }
    { StateRootLease reacquired(root); }
    require(std::filesystem::exists(root / L".msime-client-server.lock"));
    auto host = test_host_options(root);
    WindowsServerOptions options;
    options.pipes.max_clients = 2;
    options.pipes.capabilities = FanyImeProtocol::RequiredCapabilities;
    options.pipes.handshake_timeout = 2000;
    options.write_timeout = 2000;
    for (size_t role = 0; role < 3; ++role)
      options.pipes.names[role] = L"\\\\.\\pipe\\msime-server-fixture-" +
                                  suffix + L"-" + std::to_wstring(role);
    const nlohmann::json launch{{"format_version", 1}, {"resources", host.at("resources")},
        {"state_root", root.u8string()}, {"pipe_namespace", "server-fixture"},
        {"preedit_style", "pinyin"}};
    // Same key-handler factory as the executable; native UI is still absent.
    WindowsServer server(
        options, host.dump(),
        preview_key_handler(PreviewConfig::parse(launch.dump())),
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; });
    require(!server.candidate_view());
    const uint64_t client =
        (static_cast<uint64_t>(GetCurrentProcessId()) << 32) | 42u;
    ClientPipe replies(options.pipes.names[1]);
    ClientPipe worker(options.pipes.names[2]);
    FanyImePipeHello reverse{};
    reverse.client_id = client;
    reverse.pipe_role = FanyImePipeRole::ToTsf;
    require(
        write_frame(replies.handle, fixture_bytes(reverse), 2000).complete());
    require(read_frame(replies.handle, sizeof(FanyImeNamedpipeDataToTsf), 2000)
                .complete());
    reverse.pipe_role = FanyImePipeRole::ToTsfWorkerThread;
    require(
        write_frame(worker.handle, fixture_bytes(reverse), 2000).complete());
    require(read_frame(worker.handle,
                       sizeof(FanyImeNamedpipeDataToTsfWorkerThread), 2000)
                .complete());
    ClientPipe main(options.pipes.names[0]);
    require(write_frame(main.handle,
                        fixture_bytes(FanyImeProtocol::Hello(client, 1)), 2000)
                .complete());
    auto ready =
        read_frame(replies.handle, sizeof(FanyImeNamedpipeDataToTsf), 2000);
    require(ready.complete() &&
            ready.frame[0] == FanyImeReplyType::ProtocolReady);
    FanyImeNamedpipeData packet{};
    packet.client_id = client;
    packet.event_type = FanyImePipeEventType::ClientActivated;
    packet.request_id = 77;
    require(write_frame(main.handle, fixture_bytes(packet), 2000).complete());
    const auto fence = *focus_ready_bytes(77);
    auto activation =
        read_frame(worker.handle, static_cast<DWORD>(fence.size()), 2000);
    require(activation.complete() && activation.frame == fence);
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.request_id = 2;
    for (char c : std::string("U4e2d ")) {
      packet.keycode =
          static_cast<uint32_t>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
      packet.wch = static_cast<FanyImeWireChar>(c == ' ' ? 0 : c);
      packet.modifiers_down = c == 'U' ? 1 : 0;
      require(write_frame(main.handle, fixture_bytes(packet), 2000).complete());
      auto marker =
          read_frame(worker.handle, static_cast<DWORD>(fence.size()), 2000);
      require(marker.complete() && marker.frame == fence);
      auto reply =
          read_frame(replies.handle, sizeof(FanyImeNamedpipeDataToTsf), 2000);
      require(reply.complete());
      if (c == ' ') {
        auto expected = *wire_bytes(candidate_commit(packet.request_id, "中"));
        require(reply.frame ==
                std::vector<uint8_t>(expected.begin(), expected.end()));
      }
      ++packet.request_id;
    }
    server.stop(); // Must cancel the now-idle Main reader before joining it.
    server.stop();
    require(!server.candidate_view());
    require(server.failure() == ControllerFailure::None);
    std::cout << "Native isolated Windows server pipeline passed\n";
  } catch (...) {
    std::cerr << "Native Windows server pipeline failed\n";
    return 1;
  }
}

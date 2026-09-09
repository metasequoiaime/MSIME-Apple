#include "CandidateClickWorker.h"
#include "CandidateLayout.h"
#include "CandidateWindow.h"
#include "ModeWindow.h"
#include "PreviewDispatcher.h"
#include "StateRootLease.h"
#include "TestHostOptions.h"
#include "WindowsServer.h"
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
      std::optional<ModePresentation> state;
      size_t commands = 0;
      const WorkerMode expected[] = {WorkerMode::Chinese,
                                     WorkerMode::English,
                                     WorkerMode::ChinesePunctuation,
                                     WorkerMode::AsciiPunctuation,
                                     WorkerMode::Fullwidth,
                                     WorkerMode::Halfwidth};
      ModeWindow modes([&] { return state; },
                       [&](const ModeClick &click) {
                         require(commands < 6 &&
                                 click.mode == expected[commands] &&
                                 click.lease.token == 77);
                         ++commands;
                       });
      require(!IsWindowVisible(modes.handle()));
      const auto foreground = GetForegroundWindow();
      state = ModePresentation{{{42, {1, 2, 3}}, 1, 77}, {}, {}, {}};
      modes.refresh();
      UpdateWindow(modes.handle());
      require(IsWindowVisible(modes.handle()) && !modes.failed());
      require(SendMessageW(modes.handle(), WM_MOUSEACTIVATE, 0, 0) ==
              MA_NOACTIVATE);
      const auto point = MAKELPARAM(5, 5);
      for (const UINT cancellation : {WM_MOUSELEAVE, WM_CANCELMODE,
                                       WM_CAPTURECHANGED}) {
        SendMessageW(modes.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
        SendMessageW(modes.handle(), cancellation, 0, 0);
        SendMessageW(modes.handle(), WM_LBUTTONUP, 0, point);
        require(commands == 0 && !modes.failed());
      }
      SendMessageW(modes.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
      SendMessageW(modes.handle(), WM_LBUTTONUP, 0, point);
      require(commands == 1 && GetForegroundWindow() == foreground);
      const auto dpi = GetDpiForWindow(modes.handle());
      for (int i = 1; i < 6; ++i) {
        const auto cell = MAKELPARAM((i % 2) * MulDiv(112, dpi, 96) + 5,
                                     (i / 2) * MulDiv(34, dpi, 96) + 5);
        SendMessageW(modes.handle(), WM_LBUTTONDOWN, MK_LBUTTON, cell);
        SendMessageW(modes.handle(), WM_LBUTTONUP, 0, cell);
      }
      require(commands == 6);
      SendMessageW(modes.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
      ++state->lease.epoch;
      SendMessageW(modes.handle(), WM_LBUTTONUP, 0, point);
      require(commands == 6);
      state.reset();
      modes.refresh();
      require(!IsWindowVisible(modes.handle()) && !modes.failed());
    }
    {
      std::optional<CandidatePresentation> value;
      const auto original_dpi = GetThreadDpiAwarenessContext();
      CandidateWindow window([&] { return value; });
      require(AreDpiAwarenessContextsEqual(original_dpi,
                                           GetThreadDpiAwarenessContext()));
      require(AreDpiAwarenessContextsEqual(
          GetWindowDpiAwarenessContext(window.handle()),
          DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2));
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
      require(AreDpiAwarenessContextsEqual(original_dpi,
                                           GetThreadDpiAwarenessContext()));
      SendMessageW(window.handle(), WM_DPICHANGED, MAKELONG(192, 192), 0);
      window.refresh();
      require(GetUpdateRect(window.handle(), nullptr, FALSE));
      UpdateWindow(window.handle());
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
      value = frame;
      size_t clicks = 0;
      CandidateWindow clickable([&] { return value; },
                                [&](const CandidateClick &click) {
                                  require(click.index == 0 &&
                                          click.session == 1 &&
                                          click.generation == 1);
                                  ++clicks;
                                });
      clickable.refresh();
      UpdateWindow(clickable.handle());
      require(SendMessageW(clickable.handle(), WM_MOUSEACTIVATE, 0, 0) ==
              MA_NOACTIVATE);
      const auto metrics =
          candidate_metrics(GetDpiForWindow(clickable.handle()));
      const auto point =
          MAKELPARAM(metrics.padding + 1, metrics.padding + metrics.row + 1);
      SendMessageW(clickable.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
      SendMessageW(clickable.handle(), WM_LBUTTONUP, 0, point);
      require(clicks == 1 && !clickable.failed());
      // Cancellation must reject the release even with an unchanged frame.
      for (const UINT cancellation : {WM_MOUSELEAVE, WM_CANCELMODE,
                                       WM_CAPTURECHANGED}) {
        SendMessageW(clickable.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
        SendMessageW(clickable.handle(), cancellation, 0, 0);
        SendMessageW(clickable.handle(), WM_LBUTTONUP, 0, point);
        require(clicks == 1 && !clickable.failed());
      }
      SendMessageW(clickable.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
      SendMessageW(clickable.handle(), WM_LBUTTONUP, 0, point);
      require(clicks == 2 && !clickable.failed());
      SendMessageW(clickable.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
      ++value->generation;
      ++value->candidates[0].generation;
      clickable.refresh();
      UpdateWindow(clickable.handle());
      SendMessageW(clickable.handle(), WM_LBUTTONUP, 0, point);
      require(clicks == 2 && !clickable.failed());
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
      try {
        StateRootLease second(root);
      } catch (...) {
        rejected = true;
      }
      require(rejected);
    }
    {
      StateRootLease reacquired(root);
    }
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
    const nlohmann::json launch{{"format_version", 1},
                                {"resources", host.at("resources")},
                                {"state_root", root.u8string()},
                                {"pipe_namespace", "server-fixture"},
                                {"preedit_style", "pinyin"}};
    // Same key-handler factory and background click path as the executable.
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
    // Keep keyboard commit coverage, then compose again for window selection.
    for (char c : std::string("U4e2d U4e2d")) {
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
    std::atomic<SelectionRequestResult> selected{
        SelectionRequestResult::Rejected};
    CandidateClickWorker clicks([&](const CandidateClick &click) {
      selected = server.request_selection(click.lease, click.session,
                                          click.generation, click.index);
    });
    struct ClickShutdown {
      WindowsServer &server;
      CandidateClickWorker &clicks;
      ~ClickShutdown() {
        clicks.request_stop();
        server.request_stop();
        clicks.stop();
      }
    } click_shutdown{server, clicks};
    CandidateWindow candidates(
        [&] { return server.candidate_view(); },
        [&](const CandidateClick &click) { require(clicks.submit(click)); });
    // Pipe receipt precedes queue confirmation. Wait for the confirmed value,
    // not a guessed delay or an independently fabricated window snapshot.
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(2);
    bool painted = false;
    while (std::chrono::steady_clock::now() < deadline) {
      const auto value = server.candidate_view();
      if (value && value->visible && !value->candidates.empty() &&
          value->candidates[0].text == "中") {
        candidates.refresh();
        UpdateWindow(candidates.handle());
        painted = IsWindowVisible(candidates.handle()) && !candidates.failed();
        if (painted)
          break;
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    require(painted);
    const auto foreground = GetForegroundWindow();
    const auto metrics =
        candidate_metrics(GetDpiForWindow(candidates.handle()));
    const auto point =
        MAKELPARAM(metrics.padding + 1, metrics.padding + metrics.row + 1);
    SendMessageW(candidates.handle(), WM_LBUTTONDOWN, MK_LBUTTON, point);
    SendMessageW(candidates.handle(), WM_LBUTTONUP, 0, point);
    const auto committed = read_frame(
        worker.handle, sizeof(FanyImeNamedpipeDataToTsfWorkerThread), 2000);
    require(committed.complete() &&
            committed.frame == ui_complete_selection("中")->worker);
    // Wait for controller confirmation before stopping; the received frame
    // alone is not proof that the background selection transaction completed.
    const auto confirmed_deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (selected.load() == SelectionRequestResult::Rejected &&
           std::chrono::steady_clock::now() < confirmed_deadline)
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    require(selected.load() == SelectionRequestResult::Sent &&
            !clicks.failed());
    candidates.refresh();
    require(!IsWindowVisible(candidates.handle()) && !candidates.failed() &&
            GetForegroundWindow() == foreground);
    server.stop(); // Must cancel the now-idle Main reader before joining it.
    clicks.stop();
    server.stop();
    require(!server.candidate_view());
    require(server.failure() == ControllerFailure::None);
    std::cout << "Native isolated Windows server pipeline passed\n";
  } catch (...) {
    std::cerr << "Native Windows server pipeline failed\n";
    return 1;
  }
}

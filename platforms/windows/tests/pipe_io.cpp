#include "PipeIo.h"
#include "windows_ipc.h"
#include <future>
#include <iostream>
#include <sddl.h>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Windows pipe test failed");
}
struct Handle {
  Handle() = default;
  Handle(const Handle &) = delete;
  Handle &operator=(const Handle &) = delete;
  HANDLE value = INVALID_HANDLE_VALUE;
  ~Handle() { close(); }
  void close() {
    if (value && value != INVALID_HANDLE_VALUE)
      CloseHandle(value);
    value = INVALID_HANDLE_VALUE;
  }
};
struct Pair {
  Handle server, client;
  Pair() {
    static unsigned serial = 0;
    // Unique test-only pipe. Protected owner-rights DACL, no Everyone/remote
    // access, no production pipe name or registration touched.
    auto name = L"\\\\.\\pipe\\MSIMEClientIoTest-" +
                std::to_wstring(GetCurrentProcessId()) + L"-" +
                std::to_wstring(++serial);
    PSECURITY_DESCRIPTOR descriptor = nullptr;
    require(ConvertStringSecurityDescriptorToSecurityDescriptorW(
        L"D:P(A;;GA;;;OW)", SDDL_REVISION_1, &descriptor, nullptr));
    SECURITY_ATTRIBUTES security{sizeof(SECURITY_ATTRIBUTES), descriptor,
                                 FALSE};
    server.value = CreateNamedPipeW(name.c_str(),
                                    PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED |
                                        FILE_FLAG_FIRST_PIPE_INSTANCE,
                                    PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE |
                                        PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                    1, 4096, 4096, 0, &security);
    LocalFree(descriptor);
    require(server.value != INVALID_HANDLE_VALUE);
    client.value =
        CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                    OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    require(client.value != INVALID_HANDLE_VALUE);
    DWORD mode = PIPE_READMODE_MESSAGE;
    require(SetNamedPipeHandleState(client.value, &mode, nullptr, nullptr));
    Handle event;
    event.value = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    require(event.value != nullptr);
    OVERLAPPED operation{};
    operation.hEvent = event.value;
    BOOL ready = ConnectNamedPipe(server.value, &operation);
    DWORD error = ready ? ERROR_SUCCESS : GetLastError();
    if (!ready && error == ERROR_IO_PENDING) {
      DWORD transferred;
      CancelIoEx(server.value, &operation);
      GetOverlappedResult(server.value, &operation, &transferred, TRUE);
      require(false); // Client was opened first; no pending connect expected.
    }
    require(ready || error == ERROR_PIPE_CONNECTED);
  }
};
} // namespace
int main() {
  try {
    for (auto size : {sizeof(FanyImePipeHello), sizeof(FanyImeNamedpipeData),
                      sizeof(FanyImeNamedpipeDataToTsfWorkerThread),
                      sizeof(FanyImeNamedpipeDataToTsf)}) {
      Pair pipe;
      std::vector<uint8_t> payload(size, 0x5A);
      auto writer = std::async(std::launch::async, [&] {
        return write_frame(pipe.client.value, payload, 2000);
      });
      auto received =
          read_frame(pipe.server.value, static_cast<DWORD>(size), 2000);
      require(writer.get().complete() && received.complete() &&
              received.frame == payload);
    }
    for (DWORD size : {3u, 5u}) {
      Pair pipe;
      auto writer = std::async(std::launch::async, [&] {
        return write_frame(pipe.client.value, std::vector<uint8_t>(size, 0x51),
                           2000);
      });
      auto received = read_frame(pipe.server.value, 4, 2000);
      require(writer.get().complete());
      require(received.status == IoStatus::MalformedFrame &&
              received.frame.empty());
    }
    {
      Pair pipe;
      auto result = read_frame(pipe.server.value, 4, 20);
      require(result.status == IoStatus::Timeout && result.frame.empty() &&
              !result.delivery_uncertain);
    }
    {
      Pair pipe;
      Handle cancel;
      cancel.value = CreateEventW(nullptr, TRUE, FALSE, nullptr);
      require(cancel.value != nullptr);
      auto canceller = std::async(std::launch::async, [&] {
        Sleep(30);
        require(SetEvent(cancel.value));
      });
      auto result = read_frame(pipe.server.value, 4, 2000, cancel.value);
      canceller.get();
      require(result.status == IoStatus::Cancelled && result.frame.empty());
      auto skipped = write_frame(pipe.server.value, {1, 2}, 2000, cancel.value);
      require(skipped.status == IoStatus::Cancelled &&
              !skipped.delivery_uncertain && skipped.transferred == 0);
    }
    {
      Pair pipe;
      pipe.client.close();
      require(read_frame(pipe.server.value, 4, 1000).status ==
              IoStatus::Disconnected);
    }
    require(read_frame(INVALID_HANDLE_VALUE, 4, 100).status ==
            IoStatus::InvalidArgument);
    std::cout << "Windows named-pipe framing, timeout, cancellation and "
                 "disconnect tests passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

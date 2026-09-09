#include "PipeHandshake.h"
#include "PipeIo.h"
#include "PipePeer.h"
#include "windows_ipc.h"
#include <cstring>
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
template <typename Packet>
std::vector<uint8_t> fixture_bytes(const Packet &packet) {
  // Test-only synthetic packets; production serializers never expose padding.
  std::vector<uint8_t> bytes(sizeof(Packet));
  std::memcpy(bytes.data(), &packet, sizeof(Packet));
  return bytes;
}
void handshakes() {
  const auto id = (static_cast<uint64_t>(GetCurrentProcessId()) << 32) | 11u;
  for (auto role :
       {FanyImePipeRole::ToTsf, FanyImePipeRole::ToTsfWorkerThread}) {
    Pair reverse;
    auto accept = std::async(std::launch::async, [&] {
      return accept_reverse(reverse.server.value, role, 2000);
    });
    FanyImePipeHello hello{};
    hello.client_id = id;
    hello.pipe_role = role;
    require(write_frame(reverse.client.value, fixture_bytes(hello), 2000)
                .complete());
    const DWORD size = role == FanyImePipeRole::ToTsf
                           ? sizeof(FanyImeNamedpipeDataToTsf)
                           : sizeof(FanyImeNamedpipeDataToTsfWorkerThread);
    auto ready = read_frame(reverse.client.value, size, 2000);
    auto registered = accept.get();
    require(registered.status == HandshakeStatus::Ready && registered.peer &&
            registered.client_id == id && ready.complete());
    require(ready.frame[0] == 9);
    for (size_t i = 1; i < ready.frame.size(); ++i)
      require(ready.frame[i] == 0);
    if (role != FanyImePipeRole::ToTsf)
      continue;
    require(accept_main(reverse.server.value, reverse.server.value,
                        *registered.peer, id,
                        FanyImeProtocol::RequiredCapabilities, 2000)
                .status == HandshakeStatus::InvalidArgument);
    for (int mode : {0, 1, 2, 3}) {
      Pair main;
      auto packet = FanyImeProtocol::Hello(id, 71);
      if (mode == 1) // Required but not implemented optional capability.
        packet.point[1] |= FanyImeProtocol::FramedVoice;
      if (mode == 2) {
        packet = {};
        packet.event_type = FanyImePipeEventType::ClientHello;
        packet.client_id = id;
      }
      if (mode == 3)
        packet.client_id = id + 1;
      auto negotiate = std::async(std::launch::async, [&] {
        return accept_main(main.server.value, reverse.server.value,
                           *registered.peer, id,
                           FanyImeProtocol::RequiredCapabilities, 2000);
      });
      require(write_frame(main.client.value, fixture_bytes(packet), 2000)
                  .complete());
      if (mode < 2) {
        auto ack = read_frame(reverse.client.value,
                              sizeof(FanyImeNamedpipeDataToTsf), 2000);
        require(ack.complete());
        FanyImeNamedpipeDataToTsf response{};
        std::memcpy(&response, ack.frame.data(), sizeof(response));
        require(response.request_id == 71);
        require((mode == 0 && FanyImeProtocol::AcceptReply(response, 71)) ||
                (mode == 1 &&
                 response.msg_type == FanyImeReplyType::ProtocolMismatch));
        require(!(FanyImeProtocol::ReplyCapabilities(response) &
                  FanyImeProtocol::FramedVoice));
      }
      auto result = negotiate.get();
      require(result.status == ((mode == 0 || mode == 2)
                                    ? HandshakeStatus::Ready
                                    : HandshakeStatus::ProtocolRejected));
      require(result.protocol.legacy == (mode == 2));
      if (mode >= 2) {
        DWORD available = 0;
        require(PeekNamedPipe(reverse.client.value, nullptr, 0, nullptr,
                              &available, nullptr));
        require(available == 0); // No legacy ACK or spoofed-client response.
      }
    }
  }
  {
    Pair pipe;
    FanyImePipeHello hello{};
    hello.client_id = id;
    hello.pipe_role = FanyImePipeRole::ToTsfWorkerThread;
    auto accept = std::async(std::launch::async, [&] {
      return accept_reverse(pipe.server.value, FanyImePipeRole::ToTsf, 2000);
    });
    require(
        write_frame(pipe.client.value, fixture_bytes(hello), 2000).complete());
    auto result = accept.get();
    require(result.status == HandshakeStatus::ProtocolRejected && !result.peer);
    require(
        accept_reverse(pipe.server.value, FanyImePipeRole::Main, 2000).status ==
        HandshakeStatus::InvalidArgument);
  }
  {
    Pair pipe;
    Handle cancel;
    cancel.value = CreateEventW(nullptr, TRUE, TRUE, nullptr);
    require(cancel.value != nullptr);
    auto result = accept_reverse(pipe.server.value, FanyImePipeRole::ToTsf,
                                 2000, cancel.value);
    require(result.status == HandshakeStatus::TransportError &&
            result.io.status == IoStatus::Cancelled && !result.peer);
  }
}
} // namespace
int main() {
  try {
    handshakes();
    {
      Pair main, reverse;
      const auto id = (static_cast<uint64_t>(GetCurrentProcessId()) << 32) | 7u;
      DWORD error = ERROR_SUCCESS;
      auto peer = PipePeer::bind(main.server.value, id, error);
      require(peer && error == ERROR_SUCCESS);
      require(peer->matches(main.server.value, id, error));
      require(peer->matches(reverse.server.value, id, error));
      require(!peer->matches(reverse.server.value, id + 1, error));
      require(error == ERROR_ACCESS_DENIED);
      require(
          !PipePeer::bind(main.server.value, id ^ (uint64_t{1} << 32), error));
      require(error == ERROR_ACCESS_DENIED);
      require(!PipePeer::bind(main.server.value, 0, error));
      require(!PipePeer::bind(main.client.value, id, error));
      require(!PipePeer::bind(INVALID_HANDLE_VALUE, id, error));
      require(DisconnectNamedPipe(main.server.value));
      require(!peer->matches(main.server.value, id, error));
    }
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
    std::cout << "Windows named-pipe peer binding, framing, timeout, "
                 "cancellation and "
                 "disconnect tests passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

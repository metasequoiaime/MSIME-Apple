#include "../src/voice/VoiceControllerConnection.h"
#include <cassert>
#include <thread>

int main() {
  using namespace msime::windows;
  using namespace FanyImeVoiceController;
  const auto name = std::wstring(L"\\\\.\\pipe\\MSIMEControllerFixture-") + std::to_wstring(GetCurrentProcessId());
  DWORD error = ERROR_SUCCESS;
  auto listener = PipeListener::create(name, error);
  assert(listener);
  std::thread client([&] {
    HANDLE pipe = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    assert(pipe != INVALID_HANDLE_VALUE);
    DWORD mode = PIPE_READMODE_MESSAGE;
    assert(SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr));
    Request request;
    request.controller_id = (uint64_t{GetCurrentProcessId()} << 32) | 7;
    request.request_id = 1;
    const auto send = [&] {
      std::vector<uint8_t> bytes(sizeof(request));
      std::memcpy(bytes.data(), &request, sizeof(request));
      assert(write_frame(pipe, bytes, 1000).complete());
    };
    send();
    auto hello = read_frame(pipe, sizeof(Reply), 1000);
    assert(hello.complete());
    Reply reply;
    std::memcpy(&reply, hello.frame.data(), sizeof(reply));
    assert(valid_reply(reply, hello.frame.size()) && reply.request_id == 1);
    request.operation = Operation::Poll;
    request.session_id = 7; // dispatcher, not transport, decides session validity
    request.request_id = 2;
    send();
    auto result = read_frame(pipe, sizeof(Reply), 1000);
    assert(result.complete());
    std::memcpy(&reply, result.frame.data(), sizeof(reply));
    assert(reply.request_id == 2 && reply.status == Status::Stale);
    send(); // replay cannot be delivered to the dispatcher
    assert(!read_frame(pipe, sizeof(Reply), 1000).complete());
    CloseHandle(pipe);
  });
  auto accepted = listener->accept(1000);
  assert(accepted.io.complete());
  auto connection = VoiceControllerConnection::accept(std::move(accepted.connection), 1000);
  assert(connection);
  auto request = connection->receive(1000);
  assert(request && request->header.request_id == 2);
  assert(!connection->receive(1000)); // cannot pipeline over an unanswered request
  Reply reply;
  reply.status = Status::Stale;
  assert(connection->reply(reply, {}, 1000));
  assert(!connection->receive(1000) && !connection->connected());
  client.join();
}

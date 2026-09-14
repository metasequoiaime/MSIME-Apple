#include "../VoiceControllerListener.h"
#include <cassert>

int main() {
  using namespace msime::windows;
  using namespace FanyImeVoiceController;
  VoiceControllerMailbox mailbox;
  std::shared_ptr<VoiceReviewResult> result;
  int cancels = 0;
  VoiceControllerDispatch dispatcher(
      {[] { return std::optional<FocusLease>({{1, {1, 1, 1}}, 1, 1}); },
       [](const auto &) { return true; },
       [&](std::string_view language) {
         assert(language == "en-US");
         result = std::make_shared<VoiceReviewResult>();
         return result;
       },
       [&](const auto &expected) {
         assert(expected == result);
         result->recognizing();
         result->complete("synthetic listener result");
         return true;
       },
       [&](const auto &expected) {
         ++cancels;
         expected->cancel();
         return true;
       }});
  const auto name =
      std::wstring(L"\\\\.\\pipe\\MSIMEControllerListenerFixture-") +
      std::to_wstring(GetCurrentProcessId());
  DWORD error = ERROR_SUCCESS;
  auto listener = VoiceControllerListener::create(mailbox, error, name);
  assert(listener && error == ERROR_SUCCESS);
  std::atomic_bool done{false};
  std::thread client([&] {
    HANDLE pipe =
        CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                    OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    assert(pipe != INVALID_HANDLE_VALUE);
    DWORD mode = PIPE_READMODE_MESSAGE;
    assert(SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr));
    Request request;
    request.controller_id = (uint64_t{GetCurrentProcessId()} << 32) | 1;
    auto exchange = [&](Operation operation, uint64_t session = 0) {
      request.operation = operation;
      request.session_id = session;
      ++request.request_id;
      const std::string language = operation == Operation::Start ? "en-US" : "";
      request.language_bytes = static_cast<uint32_t>(language.size());
      std::vector<uint8_t> frame(sizeof(Request) + language.size());
      std::memcpy(frame.data(), &request, sizeof(Request));
      if (!language.empty())
        std::memcpy(frame.data() + sizeof(Request), language.data(),
                    language.size());
      assert(write_frame(pipe, frame, 2000).complete());
      auto message = read_message(pipe, sizeof(Reply) + MaxTextBytes, 2000);
      assert(message.complete() && message.frame.size() >= sizeof(Reply));
      VoiceControllerResponse response;
      std::memcpy(&response.header, message.frame.data(), sizeof(Reply));
      assert(valid_reply(response.header, message.frame.size()));
      assert(response.header.request_id == request.request_id);
      response.text.assign(
          reinterpret_cast<const char *>(message.frame.data() + sizeof(Reply)),
          response.header.text_bytes);
      return response;
    };
    assert(exchange(Operation::Hello).header.status == Status::Ok);
    auto start = exchange(Operation::Start);
    assert(start.header.phase == Phase::Recording && start.header.session_id);
    auto stop = exchange(Operation::Stop, start.header.session_id);
    assert(stop.header.phase == Phase::Complete &&
           stop.text == "synthetic listener result");
    assert(exchange(Operation::Poll, start.header.session_id).text ==
           stop.text);
    CloseHandle(pipe); // worker invalidates ownership; control thread cancels
    done.store(true);
  });
  const auto deadline = GetTickCount64() + 10000;
  while ((!done.load() || cancels == 0) && GetTickCount64() < deadline) {
    dispatcher.maintain();
    if (auto job = mailbox.take())
      job->complete(dispatcher.dispatch(job->channel, job->request));
    Sleep(1);
  }
  assert(done.load() && cancels == 1);
  client.join();
  listener->stop();
  assert(listener->failure() == ERROR_SUCCESS);
  listener.reset();

  // Shutdown must not depend on the UI/control thread servicing a queued job.
  const auto pending_name = name + L"-pending";
  auto pending_listener =
      VoiceControllerListener::create(mailbox, error, pending_name);
  assert(pending_listener);
  std::thread pending_client([&] {
    HANDLE pipe =
        CreateFileW(pending_name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                    nullptr, OPEN_EXISTING, FILE_FLAG_OVERLAPPED, nullptr);
    assert(pipe != INVALID_HANDLE_VALUE);
    DWORD mode = PIPE_READMODE_MESSAGE;
    assert(SetNamedPipeHandleState(pipe, &mode, nullptr, nullptr));
    Request request;
    request.controller_id = (uint64_t{GetCurrentProcessId()} << 32) | 2;
    request.request_id = 1;
    std::vector<uint8_t> frame(sizeof(Request));
    std::memcpy(frame.data(), &request, sizeof(Request));
    assert(write_frame(pipe, frame, 2000).complete());
    assert(read_message(pipe, sizeof(Reply), 2000).complete());
    request.operation = Operation::Start;
    request.language_bytes = 2;
    request.request_id = 2;
    frame.resize(sizeof(Request) + 2);
    std::memcpy(frame.data(), &request, sizeof(Request));
    frame[sizeof(Request)] = 'e';
    frame[sizeof(Request) + 1] = 'n';
    assert(write_frame(pipe, frame, 2000).complete());
    assert(!read_message(pipe, sizeof(Reply), 3000).complete());
    CloseHandle(pipe);
  });
  std::shared_ptr<VoiceControllerJob> pending;
  const auto queue_deadline = GetTickCount64() + 3000;
  while (!pending && GetTickCount64() < queue_deadline) {
    pending = mailbox.take();
    Sleep(1);
  }
  assert(pending);
  pending_listener->stop();
  pending_client.join();
  assert(!pending->channel->alive.load());
  assert(
      dispatcher.dispatch(pending->channel, pending->request).header.status ==
      Status::Stale);
}

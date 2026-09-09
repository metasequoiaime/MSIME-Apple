#include "PipeIo.h"
#include <utility>

namespace msime::windows {
namespace {
constexpr DWORD MaxFrameBytes = 16 * 1024;
IoStatus error_status(DWORD error) {
  switch (error) {
  case ERROR_BROKEN_PIPE:
  case ERROR_PIPE_NOT_CONNECTED:
  case ERROR_NO_DATA:
    return IoStatus::Disconnected;
  case ERROR_MORE_DATA:
    return IoStatus::MalformedFrame;
  case ERROR_OPERATION_ABORTED:
    return IoStatus::Cancelled;
  default:
    return IoStatus::Failed;
  }
}
struct Event {
  HANDLE handle = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  ~Event() {
    if (handle)
      CloseHandle(handle);
  }
};
IoResult transfer(HANDLE pipe, std::vector<uint8_t> &buffer, bool writing,
                  DWORD timeout, HANDLE cancel) {
  if (!pipe || pipe == INVALID_HANDLE_VALUE || buffer.empty() ||
      buffer.size() > MaxFrameBytes || !timeout || timeout == INFINITE)
    return {IoStatus::InvalidArgument, ERROR_INVALID_PARAMETER, 0, false, {}};
  DWORD mode = 0, flags = 0;
  if (!GetNamedPipeInfo(pipe, &flags, nullptr, nullptr, nullptr) ||
      !GetNamedPipeHandleStateW(pipe, &mode, nullptr, nullptr, nullptr, nullptr,
                                0))
    return {IoStatus::InvalidArgument, GetLastError(), 0, false, {}};
  if (!(flags & PIPE_TYPE_MESSAGE) || !(mode & PIPE_READMODE_MESSAGE) ||
      (mode & PIPE_NOWAIT))
    return {IoStatus::InvalidArgument, ERROR_INVALID_PARAMETER, 0, false, {}};
  if (cancel) {
    auto ready = WaitForSingleObject(cancel, 0);
    if (ready == WAIT_OBJECT_0)
      return {IoStatus::Cancelled, ERROR_OPERATION_ABORTED, 0, false, {}};
    if (ready != WAIT_TIMEOUT)
      return {IoStatus::InvalidArgument, GetLastError(), 0, false, {}};
  }
  Event event;
  if (!event.handle)
    return {IoStatus::Failed, GetLastError(), 0, false, {}};
  OVERLAPPED operation{};
  operation.hEvent = event.handle;
  DWORD transferred = 0;
  const DWORD size = static_cast<DWORD>(buffer.size());
  BOOL completed =
      writing ? WriteFile(pipe, buffer.data(), size, &transferred, &operation)
              : ReadFile(pipe, buffer.data(), size, &transferred, &operation);
  DWORD error = completed ? ERROR_SUCCESS : GetLastError();
  if (!completed && error == ERROR_IO_PENDING) {
    HANDLE events[] = {event.handle, cancel};
    const DWORD wait =
        WaitForMultipleObjects(cancel ? 2 : 1, events, FALSE, timeout);
    if (wait != WAIT_OBJECT_0) {
      const DWORD wait_error =
          wait == WAIT_FAILED ? GetLastError() : ERROR_SUCCESS;
      // CancelIoEx requests cancellation, including the race where the
      // operation finished just before cancellation. Always drain it.
      CancelIoEx(pipe, &operation);
      GetOverlappedResult(pipe, &operation, &transferred, TRUE);
      if (wait == WAIT_TIMEOUT)
        return {IoStatus::Timeout, WAIT_TIMEOUT, transferred, writing, {}};
      if (cancel && wait == WAIT_OBJECT_0 + 1)
        return {IoStatus::Cancelled,
                ERROR_OPERATION_ABORTED,
                transferred,
                writing,
                {}};
      return {IoStatus::Failed, wait_error, transferred, writing, {}};
    }
    completed = GetOverlappedResult(pipe, &operation, &transferred, FALSE);
    error = completed ? ERROR_SUCCESS : GetLastError();
  }
  if (!completed)
    return {error_status(error), error, transferred, writing, {}};
  if (transferred != size)
    return {
        IoStatus::MalformedFrame, ERROR_BAD_LENGTH, transferred, writing, {}};
  // Complete means only that this I/O completed, not that the peer applied a
  // commit. Route ownership still must be checked before confirming a reply.
  return {IoStatus::Complete, ERROR_SUCCESS, transferred, false, {}};
}
} // namespace
IoResult read_frame(HANDLE pipe, DWORD expected, DWORD timeout, HANDLE cancel) {
  if (!expected || expected > MaxFrameBytes)
    return {IoStatus::InvalidArgument, ERROR_INVALID_PARAMETER, 0, false, {}};
  std::vector<uint8_t> buffer(expected);
  auto result = transfer(pipe, buffer, false, timeout, cancel);
  if (result.complete())
    result.frame = std::move(buffer);
  return result;
}
IoResult write_frame(HANDLE pipe, const std::vector<uint8_t> &frame,
                     DWORD timeout, HANDLE cancel) {
  if (frame.empty() || frame.size() > MaxFrameBytes)
    return {IoStatus::InvalidArgument, ERROR_INVALID_PARAMETER, 0, false, {}};
  // Own the I/O buffer until completion even if a caller changes its source.
  auto buffer = frame;
  return transfer(pipe, buffer, true, timeout, cancel);
}
} // namespace msime::windows

#pragma once
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <cstdint>
#include <vector>
#include <windows.h>

namespace msime::windows {
enum class IoStatus {
  Complete,
  InvalidArgument,
  Timeout,
  Cancelled,
  Disconnected,
  MalformedFrame,
  Failed
};
struct IoResult {
  IoStatus status = IoStatus::Failed;
  DWORD system_error = ERROR_SUCCESS;
  DWORD transferred = 0;
  // A submitted write that did not complete definitively may already have
  // affected the peer. Never blindly replay the corresponding Engine action.
  bool delivery_uncertain = false;
  std::vector<uint8_t> frame; // Populated only by a complete, exact-size read.
  bool complete() const { return status == IoStatus::Complete; }
};
// Borrowed handles must remain valid and must NOT be closed concurrently.
// pipe: connected, exclusive, FILE_FLAG_OVERLAPPED, message-type/message-read.
// cancel_event: optional caller-owned manual-reset event. One operation at a
// time per handle; run on a pipe I/O worker, never the Server/TSF input thread.
// Close/reconnect after any non-complete submitted operation: an oversized
// read can leave a message suffix and cancellation can race with completion.
// The finite timeout starts cancellation; completion must be drained before
// releasing OVERLAPPED/buffers, so it is not a hard wall-clock return
// guarantee.
// Variable-length message read for the session-less Aux endpoint, which carries
// no length prefix. A short read is a complete message; a message larger than
// max_bytes is MalformedFrame (ERROR_MORE_DATA) rather than a truncated prefix,
// and a zero-length message is rejected. Close the connection after any
// non-complete result: an oversized read leaves a suffix in the pipe.
IoResult read_message(HANDLE pipe, DWORD max_bytes, DWORD timeout_ms,
                      HANDLE cancel_event = nullptr);
IoResult read_frame(HANDLE pipe, DWORD expected_bytes, DWORD timeout_ms,
                    HANDLE cancel_event = nullptr);
// Reads one complete message from a connected message-mode pipe. Unlike
// read_frame(), the payload may be shorter than max_bytes.
IoResult read_message(HANDLE pipe, DWORD max_bytes, DWORD timeout_ms,
                      HANDLE cancel_event = nullptr);
// Established input stream only: no idle deadline, but cancellation is
// mandatory and still drained before releasing the operation or buffer.
// Do not use for handshakes or writes, which must retain finite deadlines.
IoResult read_frame_until_cancel(HANDLE pipe, DWORD expected_bytes,
                                 HANDLE cancel_event);
IoResult write_frame(HANDLE pipe, const std::vector<uint8_t> &frame,
                     DWORD timeout_ms, HANDLE cancel_event = nullptr);
} // namespace msime::windows

#pragma once
#include <cstdint>
#include <cstring>
#include <optional>
#include <string>
#include <vector>

#include "../../vendor/MSIME-Engine/contracts/windows_ipc.h"

namespace msime::windows {
// One decoded batch of TIP diagnostics.
//
// The TIP side of this was ported in full - the bounded queue, the 250 ms
// flush and the writer - but the Server never opened the pipe, so turning
// diagnostic logging on produced nothing and TIP-side composition and key
// faults stayed undiagnosable in the field.
struct DiagnosticBatch {
  uint32_t record_count = 0;
  // Records the TIP had to drop because its own queue was full. Carried so a
  // gap in the log is visible rather than silently absent.
  uint32_t dropped_count = 0;
  uint32_t source_process_id = 0;
  // UTF-8 payload, exactly payload_bytes long.
  std::string payload;
};

// Decode one frame. Everything is validated against the shared contract before
// any of it is believed: this arrives from another process, and a header that
// disagrees with the frame it came in is not a batch worth keeping.
inline std::optional<DiagnosticBatch>
parse_diagnostic_batch(const void *bytes, size_t length) {
  constexpr size_t header_size = 28;
  static_assert(sizeof(FanyImeTsfDiagnosticBatchHeader) >= header_size,
                "The diagnostic header must cover the documented 28 bytes.");
  if (!bytes || length < header_size ||
      length > FANY_IME_TSF_DIAGNOSTIC_MAX_FRAME_BYTES)
    return std::nullopt;
  const auto *raw = static_cast<const uint8_t *>(bytes);
  auto field = [raw](size_t offset) {
    uint32_t value = 0;
    std::memcpy(&value, raw + offset, sizeof(value));
    return value;
  };
  if (field(0) != FANY_IME_TSF_DIAGNOSTIC_MAGIC)
    return std::nullopt;
  if (field(4) != FANY_IME_TSF_DIAGNOSTIC_VERSION)
    return std::nullopt;
  // The header declares its own size; a different one means a different
  // layout, so the offsets below would be reading the wrong fields.
  if (field(8) != header_size)
    return std::nullopt;
  const auto payload_bytes = field(12);
  // The payload has to be exactly what the frame carried. A shorter frame
  // would have us read past it; a longer one means the two disagree.
  if (payload_bytes != length - header_size)
    return std::nullopt;
  DiagnosticBatch batch;
  batch.record_count = field(16);
  batch.dropped_count = field(20);
  batch.source_process_id = field(24);
  // Records without a payload, or a payload without records, is a malformed
  // pair either way.
  if ((batch.record_count == 0) != (payload_bytes == 0))
    return std::nullopt;
  batch.payload.assign(reinterpret_cast<const char *>(raw + header_size),
                       payload_bytes);
  // Diagnostics are text; a control byte means this is not the payload the
  // contract describes, and it must not reach a log verbatim.
  for (unsigned char ch : batch.payload)
    if (ch < 0x09 || (ch > 0x0d && ch < 0x20))
      return std::nullopt;
  return batch;
}
} // namespace msime::windows

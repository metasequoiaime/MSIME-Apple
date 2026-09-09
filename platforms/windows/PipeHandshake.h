#pragma once
#include "PipeIo.h"
#include "PipePeer.h"
#include "ipc_negotiation.h"

namespace msime::windows {
enum class HandshakeStatus {
  Ready,
  InvalidArgument,
  TransportError,
  IdentityRejected,
  ProtocolRejected
};
struct ReverseHandshake {
  HandshakeStatus status = HandshakeStatus::InvalidArgument;
  IoResult io;
  uint64_t client_id = 0;
  std::unique_ptr<PipePeer> peer;
};
struct MainHandshake {
  HandshakeStatus status = HandshakeStatus::InvalidArgument;
  IoResult io;
  FanyImeProtocol::Negotiation protocol;
};
// Worker-only, borrowed exclusive handles; timeout applies per I/O operation.
// The caller enforces local DACLs, prevents endpoint replacement/closure and
// excludes ALL other writers until these functions return. No registry is
// modified here. Publish a reverse endpoint only after Ready; bind any main
// result to the same registration generation before permitting activation.
// Only status == Ready permits that next step; io.complete() or an accepted
// negotiation alone does not. Close rejected endpoints; never retry an ACK
// with uncertain delivery on the same registration.
ReverseHandshake accept_reverse(HANDLE pipe, uint32_t expected_role,
                                DWORD timeout_ms, HANDLE cancel = nullptr);
// reply_pipe MUST be a Ready ToTsf endpoint, not the worker endpoint, belonging
// to reverse_peer/client_id. Hold its registration/lifetime guard throughout.
// Capabilities are supplied by the actual dispatcher; no optional feature is
// advertised by default. Ready is protocol readiness, NOT focus ownership.
MainHandshake accept_main(HANDLE main_pipe, HANDLE reply_pipe,
                          const PipePeer &reverse_peer, uint64_t client_id,
                          uint32_t implemented_capabilities, DWORD timeout_ms,
                          HANDLE cancel = nullptr);
} // namespace msime::windows

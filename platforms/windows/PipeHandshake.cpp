#include "PipeHandshake.h"
#include "ReplyCodec.h"
#include <cstring>

namespace msime::windows {
ReverseHandshake accept_reverse(HANDLE pipe, uint32_t role, DWORD timeout,
                                HANDLE cancel) {
  ReverseHandshake result;
  const auto ready = pipe_ready_bytes(role);
  if (!ready)
    return result;
  result.io = read_frame(pipe, sizeof(FanyImePipeHello), timeout, cancel);
  if (!result.io.complete()) {
    result.status = HandshakeStatus::TransportError;
    return result;
  }
  FanyImePipeHello hello{};
  std::memcpy(&hello, result.io.frame.data(), sizeof(hello));
  result.io.frame.clear();
  if (!hello.client_id || hello.pipe_role != role) {
    result.status = HandshakeStatus::ProtocolRejected;
    return result;
  }
  DWORD error = ERROR_SUCCESS;
  auto peer = PipePeer::bind(pipe, hello.client_id, error);
  if (!peer) {
    result.status = HandshakeStatus::IdentityRejected;
    result.io.system_error = error;
    return result;
  }
  result.io = write_frame(pipe, *ready, timeout, cancel);
  if (!result.io.complete()) {
    result.status = HandshakeStatus::TransportError;
    return result;
  }
  result.client_id = hello.client_id;
  result.peer = std::move(peer);
  result.status = HandshakeStatus::Ready;
  return result;
}
MainHandshake accept_main(HANDLE main_pipe, HANDLE reply_pipe,
                          const PipePeer &peer, uint64_t client_id,
                          uint32_t capabilities, DWORD timeout, HANDLE cancel) {
  MainHandshake result;
  if (main_pipe == reply_pipe ||
      (capabilities & FanyImeProtocol::RequiredCapabilities) !=
          FanyImeProtocol::RequiredCapabilities)
    return result;
  DWORD error = ERROR_SUCCESS;
  if (!peer.matches(main_pipe, client_id, error) ||
      !peer.matches(reply_pipe, client_id, error)) {
    result.status = HandshakeStatus::IdentityRejected;
    result.io.system_error = error;
    return result;
  }
  result.io =
      read_frame(main_pipe, sizeof(FanyImeNamedpipeData), timeout, cancel);
  if (!result.io.complete()) {
    result.status = HandshakeStatus::TransportError;
    return result;
  }
  FanyImeNamedpipeData hello{};
  std::memcpy(&hello, result.io.frame.data(), sizeof(hello));
  result.io.frame.clear();
  if (hello.client_id != client_id ||
      hello.event_type != FanyImePipeEventType::ClientHello) {
    result.status = HandshakeStatus::ProtocolRejected;
    return result;
  }
  result.protocol = FanyImeProtocol::Negotiate(hello, capabilities);
  // Recheck after the potentially blocking read, before sending an ACK.
  if (!peer.matches(main_pipe, client_id, error) ||
      !peer.matches(reply_pipe, client_id, error)) {
    result.status = HandshakeStatus::IdentityRejected;
    result.io.system_error = error;
    return result;
  }
  if (!result.protocol.legacy) {
    const auto reply =
        protocol_reply_bytes(FanyImeProtocol::Reply(hello, result.protocol));
    if (!reply) {
      result.status = HandshakeStatus::ProtocolRejected;
      return result;
    }
    result.io = write_frame(reply_pipe, {reply->begin(), reply->end()}, timeout,
                            cancel);
    if (!result.io.complete()) {
      result.status = HandshakeStatus::TransportError;
      return result;
    }
  }
  result.status = result.protocol.accepted ? HandshakeStatus::Ready
                                           : HandshakeStatus::ProtocolRejected;
  return result;
}
} // namespace msime::windows

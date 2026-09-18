#pragma once
#include "PipeIo.h"
#include "PipeListener.h"
#include "PipePeer.h"
#include "VoiceControllerProtocol.h"
#include <memory>
#include <optional>

namespace msime::windows {
// One I/O worker exclusively owns this connection. It does not own microphone
// or TSF state, and may not execute callbacks while holding the UI/focus lock.
// The dispatcher must separately bind/revalidate its Server-owned target lease
// and invalidate queued work on connection loss. Destruction follows drained
// I/O; cancel handles are borrowed only for each synchronous operation.
class VoiceControllerConnection final {
public:
  static std::unique_ptr<VoiceControllerConnection> accept(
      std::unique_ptr<PipeConnection> connection, DWORD timeout, HANDLE cancel = nullptr) {
    using namespace FanyImeVoiceController;
    if (!connection || !timeout || timeout == INFINITE) return nullptr;
    const auto message = read_message(connection->handle(), sizeof(Request) + MaxLanguageBytes, timeout, cancel);
    if (!message.complete()) return nullptr;
    const auto hello = decode_voice_controller_request(message.frame);
    if (!hello || hello->header.operation != Operation::Hello) return nullptr;
    DWORD error = ERROR_SUCCESS;
    auto peer = PipePeer::bind(connection->handle(), hello->header.controller_id, error);
    if (!peer) return nullptr;
    Reply reply;
    reply.request_id = hello->header.request_id;
    const auto encoded = encode_voice_controller_reply(reply);
    if (!encoded || !peer->matches(connection->handle(), hello->header.controller_id, error) ||
        !write_frame(connection->handle(), *encoded, timeout, cancel).complete()) return nullptr;
    return std::unique_ptr<VoiceControllerConnection>(new VoiceControllerConnection(
        std::move(connection), std::move(peer), hello->header.controller_id, hello->header.request_id));
  }

  VoiceControllerConnection(const VoiceControllerConnection &) = delete;
  VoiceControllerConnection &operator=(const VoiceControllerConnection &) = delete;

  std::optional<VoiceControllerRequest> receive(DWORD timeout, HANDLE cancel = nullptr) {
    using namespace FanyImeVoiceController;
    if (!connection_ || pending_ || !timeout || timeout == INFINITE) return std::nullopt;
    const auto message = read_message(connection_->handle(), sizeof(Request) + MaxLanguageBytes, timeout, cancel);
    const auto request = message.complete() ? decode_voice_controller_request(message.frame) : std::nullopt;
    DWORD error = ERROR_SUCCESS;
    if (!request || request->header.operation == Operation::Hello ||
        request->header.controller_id != controller_ || request->header.request_id <= last_request_ ||
        !peer_->matches(connection_->handle(), controller_, error)) {
      close();
      return std::nullopt;
    }
    last_request_ = request->header.request_id;
    pending_ = last_request_;
    return request;
  }

  bool reply(FanyImeVoiceController::Reply response, std::string_view text,
             DWORD timeout, HANDLE cancel = nullptr) {
    if (!connection_ || !pending_ || !timeout || timeout == INFINITE) return false;
    response.request_id = *pending_;
    const auto encoded = encode_voice_controller_reply(response, text);
    DWORD error = ERROR_SUCCESS;
    if (!encoded || !peer_->matches(connection_->handle(), controller_, error) ||
        !write_frame(connection_->handle(), *encoded, timeout, cancel).complete()) {
      close();
      return false;
    }
    pending_.reset();
    return true;
  }

  bool connected() const { return connection_ != nullptr; }
  void close() {
    pending_.reset();
    peer_.reset();
    connection_.reset();
  }

private:
  VoiceControllerConnection(std::unique_ptr<PipeConnection> connection,
                            std::unique_ptr<PipePeer> peer, uint64_t controller, uint64_t request)
      : connection_(std::move(connection)), peer_(std::move(peer)),
        controller_(controller), last_request_(request) {}
  std::unique_ptr<PipeConnection> connection_;
  std::unique_ptr<PipePeer> peer_;
  uint64_t controller_;
  uint64_t last_request_;
  std::optional<uint64_t> pending_;
};
} // namespace msime::windows

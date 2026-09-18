#pragma once
#include "FocusGate.h"
#include "VoiceReviewResult.h"
#include <atomic>
#include <functional>
#include <limits>

namespace msime::windows {
// Created only after VoiceControllerConnection authenticated Hello. Object
// identity is connection identity; a reconnect never inherits a session.
struct VoiceControllerChannel {
  std::atomic_bool alive{true};
};
struct VoiceControllerResponse {
  FanyImeVoiceController::Reply header;
  std::string text;
};

// Entire dispatcher (including destruction) is control-thread only. Backend
// callbacks must not wait for the pipe worker or run under the focus gate.
class VoiceControllerDispatch final {
public:
  using Result = std::shared_ptr<VoiceReviewResult>;
  struct Backend {
    std::function<std::optional<FocusLease>()> focus;
    std::function<bool(const FocusLease &)> valid;
    std::function<Result(std::string_view)> start;
    std::function<bool(const Result &)> stop;
    std::function<bool(const Result &)> cancel;
  };
  explicit VoiceControllerDispatch(Backend backend)
      : backend_(std::move(backend)) {}
  ~VoiceControllerDispatch() { retire(); }
  VoiceControllerDispatch(const VoiceControllerDispatch &) = delete;
  VoiceControllerDispatch &operator=(const VoiceControllerDispatch &) = delete;

  void maintain() noexcept {
    try {
      if (current_ && (!current_->channel->alive.load() ||
                       !backend_.valid(current_->lease)))
        retire();
    } catch (...) {
      retire();
    }
  }
  void retire() noexcept {
    if (!current_)
      return;
    auto previous = std::move(*current_);
    current_.reset();
    // Scrub even a completed result, including when the backend already moved
    // on to a different native capture and refuses the matching-object cancel.
    previous.result->cancel();
    try {
      (void)backend_.cancel(previous.result);
    } catch (...) {
    }
  }
  VoiceControllerResponse
  dispatch(const std::shared_ptr<VoiceControllerChannel> &channel,
           const VoiceControllerRequest &request) {
    using namespace FanyImeVoiceController;
    VoiceControllerResponse response;
    response.header.request_id = request.header.request_id;
    const auto error = [&](Status status) {
      response = {};
      response.header.request_id = request.header.request_id;
      response.header.status = status;
      return response;
    };
    if (!channel || !channel->alive.load())
      return error(Status::Stale);
    if (!valid_request(request.header,
                       sizeof(Request) + request.language.size()) ||
        request.header.operation == Operation::Hello)
      return error(Status::Invalid);
    try {
      maintain();
      if (request.header.operation == Operation::Start) {
        if (current_ && current_->result->active())
          return error(Status::Busy);
        if (next_session_ == std::numeric_limits<uint64_t>::max())
          return error(Status::Unavailable);
        const auto lease = backend_.focus();
        if (!lease || !lease->epoch || !lease->token || !backend_.valid(*lease))
          return error(Status::Unavailable);
        retire();
        auto result = backend_.start(request.language);
        if (!result)
          return error(Status::Unavailable);
        current_ = Session{channel, ++next_session_, *lease, std::move(result)};
        // start can open a device/network stream. Focus or connection may have
        // changed while it ran. No text or session is returned without recheck.
        if (!channel->alive.load() || !backend_.valid(*lease)) {
          retire();
          return error(Status::Stale);
        }
      } else {
        if (!current_ || current_->channel != channel ||
            current_->id != request.header.session_id)
          return error(Status::Stale);
        if (request.header.operation == Operation::Cancel) {
          current_->result->cancel();
          (void)backend_.cancel(current_->result);
        } else if (request.header.operation == Operation::Stop &&
                   !backend_.stop(current_->result)) {
          retire();
          return error(Status::Stale);
        }
      }
      maintain();
      if (!current_)
        return error(Status::Stale);
      const auto snapshot = current_->result->snapshot();
      response.header.session_id = current_->id;
      response.header.phase = snapshot.phase;
      response.header.level = snapshot.level;
      response.text = snapshot.text;
      response.header.text_bytes = static_cast<uint32_t>(response.text.size());
      return response;
    } catch (...) {
      retire();
      return error(Status::Unavailable);
    }
  }

private:
  struct Session {
    std::shared_ptr<VoiceControllerChannel> channel;
    uint64_t id;
    FocusLease lease;
    Result result;
  };
  Backend backend_;
  uint64_t next_session_ = 0;
  std::optional<Session> current_;
};
} // namespace msime::windows

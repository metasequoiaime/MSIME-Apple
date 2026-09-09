#include "FocusedSession.h"
#include <stdexcept>

namespace msime::windows {
void FocusedSession::check_thread() const {
  if (std::this_thread::get_id() != thread_)
    throw std::logic_error("Wrong focused session thread");
}
bool FocusedSession::prepared(const FocusLease &lease) const {
  return lease_ && composer_ && lease_->epoch == lease.epoch &&
         lease_->token == lease.token &&
         same_ticket(lease_->transport, lease.transport);
}
bool FocusedSession::prepare(const FocusLease &lease) {
  check_thread();
  if (lease.transport.client != client_)
    return false;
  try {
    return gate_.with_pending(lease, [&] {
      if (prepared(lease))
        return;
      if (composer_)
        composer_->cancel();
      session_.activate(lease.epoch);
      composer_.emplace(client_, lease.epoch);
      lease_ = lease;
    });
  } catch (...) {
    gate_.deactivate(lease);
    composer_.reset();
    lease_.reset();
    throw;
  }
}
std::optional<PendingReply>
FocusedSession::key(const FocusLease &lease, const FanyImeNamedpipeData &packet,
                    ReplyPath path, bool uiless,
                    std::optional<std::string> local_text) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->dispatch(session_, packet, lease.epoch, path, uiless,
                                 std::move(local_text));
  });
  return result;
}
bool FocusedSession::confirm(const FocusLease &lease, uint64_t request) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    composer_->confirm_delivery(client_, lease.epoch, request);
  });
}
std::optional<PendingReply> FocusedSession::pending(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      result = composer_->pending();
  });
  return result;
}
bool FocusedSession::cancel(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return false;
  // This can be cleanup for a previous owner; don't invalidate a new lease.
  gate_.deactivate(lease);
  composer_->cancel();
  session_.deactivate(lease.epoch);
  composer_.reset();
  lease_.reset();
  return true;
}
std::optional<nlohmann::json>
FocusedSession::update_preferences(const FocusLease &lease,
                                   const std::string &snapshot) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    if (!composer_->has_pending())
      result = session_.update_preferences(lease.epoch, snapshot);
  });
  return result;
}
} // namespace msime::windows

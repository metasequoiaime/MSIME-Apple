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
      preferences_retry_.reset();
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
std::optional<PendingReply> FocusedSession::edit(const FocusLease &lease,
    const FanyImeNamedpipeData &packet, TsfPreeditStyle style) {
  check_thread();
  if (!prepared(lease)) return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] { result = composer_->edit(session_, packet, lease.epoch, style); });
  return result;
}
std::optional<PendingReply> FocusedSession::basic_key(
    const FocusLease &lease, const FanyImeNamedpipeData &packet,
    TsfPreeditStyle style, std::optional<std::string> local_text) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->basic_key(session_, packet, lease.epoch, style,
                                  std::move(local_text));
  });
  return result;
}
std::optional<PendingReply>
FocusedSession::navigate(const FocusLease &lease,
                         const FanyImeNamedpipeData &packet,
                         const NavigationBindings &bindings) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->navigate(session_, packet, lease.epoch, bindings);
  });
  return result;
}
bool FocusedSession::confirm(const FocusLease &lease, uint64_t request) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    composer_->confirm_delivery(client_, lease.epoch, request);
    if (preferences_retry_) {
      session_.update_preferences(lease.epoch, preferences_retry_->dump());
      preferences_retry_.reset();
    }
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
bool FocusedSession::set_input_enabled(const FocusLease &lease, bool enabled) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      throw std::logic_error("Input mode changed before reply delivery");
    session_.set_input_enabled(lease.epoch, enabled);
    if (!enabled)
      composer_->cancel();
  });
}
bool FocusedSession::set_chinese_punctuation(const FocusLease &lease, bool enabled) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      throw std::logic_error("Punctuation mode changed before reply delivery");
    session_.set_chinese_punctuation(lease.epoch, enabled);
  });
}
bool FocusedSession::cancel(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return false;
  // This can be cleanup for a previous owner; don't invalidate a new lease.
  gate_.deactivate(lease);
  composer_->cancel();
  preferences_retry_.reset();
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
bool FocusedSession::queue_current_preferences(const std::string &snapshot) {
  check_thread();
  return lease_ && queue_preferences(*lease_, snapshot);
}
bool FocusedSession::queue_preferences(const FocusLease &lease,
                                       const std::string &snapshot) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    if (snapshot.empty() || snapshot.size() > 16384)
      throw std::invalid_argument("Invalid preferences snapshot size");
    auto document = nlohmann::json::parse(snapshot);
    if (!document.is_object() || !document.contains("revision") ||
        !document.at("revision").is_number_unsigned() ||
        document.value("format_version", 0) != 1 ||
        !document.contains("preferences") ||
        !document.at("preferences").is_object())
      throw std::invalid_argument("Invalid preferences snapshot envelope");
    if (preferences_retry_) {
      const auto revision = document.at("revision").get<uint64_t>();
      const auto previous = preferences_retry_->at("revision").get<uint64_t>();
      if (revision < previous ||
          (revision == previous && document != *preferences_retry_))
        throw std::invalid_argument("Stale or conflicting queued preferences");
    }
    if (composer_->has_pending())
      preferences_retry_ = std::move(document);
    else {
      session_.update_preferences(lease.epoch, snapshot);
      preferences_retry_.reset();
    }
  });
}
std::optional<PendingReply> FocusedSession::configured_key(
    const FocusLease &lease, const FanyImeNamedpipeData &packet,
    TsfPreeditStyle style, const NavigationBindings &bindings,
    std::optional<std::string> local_text) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->configured_key(session_, packet, lease.epoch, style,
                                       bindings, std::move(local_text));
  });
  return result;
}
} // namespace msime::windows

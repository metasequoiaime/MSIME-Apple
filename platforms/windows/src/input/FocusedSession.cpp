#include "FocusedSession.h"
#include <ctime>
#include <memory>
#include <stdexcept>
#include <thread>
#include <utility>

namespace msime::windows {
std::string
FocusedSession::typing_statistics_directory(const std::string &options) {
  try {
    return nlohmann::json::parse(options).value("preferences_directory",
                                                std::string{});
  } catch (...) {
    // Statistics are optional. A configuration this session already accepted
    // must not be re-litigated here.
    return {};
  }
}
std::optional<FocusedSession::Commit> FocusedSession::pending_commit() const {
  if (!composer_ || !composer_->has_pending())
    return std::nullopt;
  const auto &reply = composer_->pending();
  if (!reply.committed_text || reply.committed_text->empty())
    return std::nullopt;
  return Commit{*reply.committed_text,
                resolve_typing_source_from_transition(reply.source.transition)};
}
void FocusedSession::record_commit(const std::optional<Commit> &delivered) {
  if (!delivered)
    return;
  if (statistics_) {
    statistics_(delivered->text, delivered->source);
    return;
  }
  if (statistics_directory_.empty())
    return;
  auto request =
      typing_statistics_record_request(statistics_directory_, delivered->text,
                                       delivered->source,
                                       local_day(std::time(nullptr)));
  if (request.empty())
    return;
  // Off the input queue: the shared store takes a file lock, and a commit must
  // never wait on statistics. Detached like the other hosts do; the request is
  // a self-contained copy, so nothing here outlives it.
  try {
    std::thread([payload = std::move(request)] {
      try {
        if (auto *raw = msime_client_typing_statistics(
                reinterpret_cast<const uint8_t *>(payload.data()),
                payload.size()))
          msime_client_string_free(raw);
      } catch (...) {
        // Best effort; text commitment has already happened.
      }
    }).detach();
  } catch (...) {
    // Thread exhaustion drops the record rather than the keystroke.
  }
}
void FocusedSession::check_thread() const {
  if (std::this_thread::get_id() != thread_)
    throw std::logic_error("Wrong focused session thread");
}
bool FocusedSession::prepared(const FocusLease &lease) const {
  return lease_ && composer_ && lease_->epoch == lease.epoch &&
         lease_->token == lease.token &&
         same_ticket(lease_->transport, lease.transport);
}
void FocusedSession::attach_online_query(
    const FocusLease &lease, std::optional<PendingReply> &reply) {
  if (reply) {
    reply->online_query = session_.online_query(lease.epoch);
    if (reply->online_query) {
      try {
        reply->ai_request =
            session_.ai_request(lease.epoch, *reply->online_query);
      } catch (...) {
        // AI configuration is optional; keep the ordinary reply path intact.
        reply->ai_request.reset();
      }
    }
    reply->translation_query = session_.translation_query(lease.epoch);
  }
}
std::optional<nlohmann::json>
FocusedSession::dedicated_english(const FocusLease &lease, bool exit) {
  check_thread();
  if (!prepared(lease) || composer_->has_pending())
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    result = session_.dedicated_english(lease.epoch, exit);
    if (exit) composer_->cancel();
  });
  return result;
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
    attach_online_query(lease, result);
  });
  return result;
}
std::optional<PendingReply> FocusedSession::edit(const FocusLease &lease,
    const FanyImeNamedpipeData &packet, TsfPreeditStyle style) {
  check_thread();
  if (!prepared(lease)) return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->edit(session_, packet, lease.epoch, style);
    attach_online_query(lease, result);
  });
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
    attach_online_query(lease, result);
  });
  return result;
}
std::optional<PendingReply> FocusedSession::toggle_character_set(
    const FocusLease &lease, const FanyImeNamedpipeData &packet, bool enabled,
    const std::function<bool(bool)> &persist) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->toggle_character_set(session_, packet, lease.epoch,
                                              enabled, persist);
    attach_online_query(lease, result);
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
    attach_online_query(lease, result);
  });
  return result;
}
bool FocusedSession::confirm(const FocusLease &lease, uint64_t request) {
  check_thread();
  if (!prepared(lease))
    return false;
  // Read before the acknowledgement, which clears the pending reply, and
  // recorded only if it went through: a throw leaves the commit unconfirmed,
  // and an unconfirmed commit is not in the document.
  const auto delivered = pending_commit();
  const bool confirmed = gate_.with_active(lease, [&] {
    composer_->confirm_delivery(client_, lease.epoch, request);
    if (preferences_retry_) {
      session_.update_preferences(lease.epoch, preferences_retry_->dump());
      preferences_retry_.reset();
    }
  });
  if (confirmed)
    record_commit(delivered);
  return confirmed;
}
std::optional<PendingReply>
FocusedSession::select_candidate(const FocusLease &lease, uint64_t session,
                                 uint64_t generation, size_t index) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->select_candidate(session_, session, generation, index);
    attach_online_query(lease, result);
  });
  return result;
}
std::optional<nlohmann::json>
FocusedSession::candidate_action(const FocusLease &lease, uint64_t session,
                                 uint64_t generation, size_t index,
                                 CandidateAction action, uint8_t position) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      return;
    const auto current = session_.view();
    if (current.at("session").get<uint64_t>() != session ||
        current.at("generation").get<uint64_t>() != generation ||
        !current.at("focused").get<bool>())
      return;
    bool found = false;
    for (const auto &candidate : current.at("candidates")) {
      const auto &id = candidate.at("id");
      if (id.at("session").get<uint64_t>() == session &&
          id.at("generation").get<uint64_t>() == generation &&
          id.at("index").get<size_t>() == index) {
        found = true;
        break;
      }
    }
    if (found)
      result = session_.candidate_action(lease.epoch, generation, index,
                                         action, position);
  });
  return result;
}
std::optional<nlohmann::json>
FocusedSession::page_candidate(const FocusLease &lease, uint64_t session,
                               uint64_t generation, bool previous,
                               unsigned steps) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      return;
    const auto current = session_.view();
    if (!current.at("focused").get<bool>() ||
        current.at("session").get<uint64_t>() != session ||
        current.at("generation").get<uint64_t>() != generation)
      return;
    result = session_.page_candidate(lease.epoch, session, generation,
                                     previous, steps);
  });
  return result;
}
bool FocusedSession::confirm_ui(const FocusLease &lease, uint64_t generation) {
  check_thread();
  if (!prepared(lease))
    return false;
  const auto delivered = pending_commit();
  const bool confirmed = gate_.with_active(lease, [&] {
    composer_->confirm_ui_delivery(client_, lease.epoch, generation);
    if (preferences_retry_) {
      session_.update_preferences(lease.epoch, preferences_retry_->dump());
      preferences_retry_.reset();
    }
  });
  if (confirmed)
    record_commit(delivered);
  return confirmed;
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
bool FocusedSession::cancel_composition(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return false;
  return gate_.with_active(lease, [&] {
    if (composer_->has_pending())
      throw std::logic_error("Composition cancelled before reply delivery");
    session_.cancel_composition(lease.epoch);
    composer_->cancel();
  });
}
bool FocusedSession::reset_cache() {
  check_thread();
  try {
    session_.reset_cache();
    return true;
  } catch (...) {
    return false;
  }
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
bool FocusedSession::cancel_focus_token(uint64_t token) {
  check_thread();
  if (!token)
    return false;
  // Not focused, or focused under a later token: the session the DLL named is
  // already gone, so there is nothing left to tear down.
  if (!lease_ || lease_->token != token)
    return true;
  return cancel(*lease_);
}
std::optional<nlohmann::json>
FocusedSession::rerank_settled(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] { result = session_.rerank_settled(lease.epoch); });
  return result;
}
std::optional<nlohmann::json>
FocusedSession::apply_cloud_response(const FocusLease &lease,
                                     const std::string &query,
                                     const std::string &body) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    result = session_.apply_cloud_response(lease.epoch, query, body);
  });
  return result;
}
std::optional<nlohmann::json>
FocusedSession::apply_ai_candidates(const FocusLease &lease,
                                    const std::string &query,
                                    const std::string &candidates) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    result = session_.apply_ai_candidates(lease.epoch, query, candidates);
  });
  return result;
}
std::optional<std::string>
FocusedSession::translation_query(const FocusLease &lease) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<std::string> result;
  gate_.with_active(lease, [&] { result = session_.translation_query(lease.epoch); });
  return result;
}
std::optional<nlohmann::json>
FocusedSession::apply_translations(const FocusLease &lease, uint64_t generation,
                                   const std::string &translations) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<nlohmann::json> result;
  gate_.with_active(lease, [&] {
    result = session_.apply_translations(lease.epoch, generation, translations);
  });
  return result;
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
    std::optional<std::string> local_text, WordCharacterBinding word_binding) {
  check_thread();
  if (!prepared(lease))
    return std::nullopt;
  std::optional<PendingReply> result;
  gate_.with_active(lease, [&] {
    result = composer_->configured_key(session_, packet, lease.epoch, style,
                                       bindings, std::move(local_text),
                                       word_binding);
    attach_online_query(lease, result);
  });
  return result;
}
} // namespace msime::windows

#include "ServerSession.h"
#include "KeyEvent.h"
#include <memory>
#include <stdexcept>

namespace msime::windows {
namespace {
nlohmann::json response(char *raw) {
  std::unique_ptr<char, decltype(&msime_client_string_free)> owned(
      raw, msime_client_string_free);
  if (!raw)
    throw std::runtime_error("Missing shared host response");
  auto document = nlohmann::json::parse(raw);
  // Do not propagate input/path-bearing raw library diagnostics to production
  // logs.
  if (!document.at("ok").get<bool>())
    throw std::runtime_error("Shared host operation failed");
  return document.at("value");
}
} // namespace
ServerSession::ServerSession(uint64_t client_id, const std::string &options)
    : client_(client_id) {
  if (!client_ || options.size() > 16384 || msime_client_abi_version() != 1)
    throw std::invalid_argument("Invalid Windows session configuration");
  auto created = response(msime_client_create(
      reinterpret_cast<const uint8_t *>(options.data()), options.size()));
  session_ = created.at("session").get<uint64_t>();
}
ServerSession::~ServerSession() {
  // Silently destroying on another thread would leak the thread-local Rust
  // session. Ownership cannot be transferred to a pipe I/O worker.
  if (std::this_thread::get_id() != thread_)
    std::terminate();
  msime_client_string_free(msime_client_destroy(session_));
}
void ServerSession::check_thread() const {
  if (std::this_thread::get_id() != thread_)
    throw std::logic_error("Wrong Server session thread");
}
void ServerSession::check_active(uint64_t epoch) const {
  check_thread();
  if (!active_ || !epoch || epoch != epoch_)
    throw std::logic_error("Expired Windows focus route");
}
nlohmann::json ServerSession::activate(uint64_t epoch) {
  check_thread();
  if (!epoch || epoch < epoch_ || (epoch == epoch_ && !active_))
    throw std::logic_error("Expired Windows activation");
  if (active_ && epoch != epoch_)
    response(msime_client_focus(session_, false));
  auto result = response(msime_client_focus(session_, input_enabled_));
  epoch_ = epoch;
  active_ = true;
  return result;
}
nlohmann::json ServerSession::deactivate(uint64_t epoch) {
  check_active(epoch);
  auto result = response(msime_client_focus(session_, false));
  active_ = false;
  return result;
}
void ServerSession::set_input_enabled(uint64_t epoch, bool enabled) {
  check_active(epoch);
  if (input_enabled_ != enabled) {
    response(msime_client_focus(session_, enabled));
    input_enabled_ = enabled;
  }
}
void ServerSession::set_chinese_punctuation(uint64_t epoch, bool enabled) {
  check_active(epoch);
  response(msime_client_set_chinese_punctuation(session_, enabled));
}
KeyResult ServerSession::key(const FanyImeNamedpipeData &packet,
                             uint64_t epoch) {
  check_active(epoch);
  const auto action = translate_key(packet);
  if (packet.client_id != client_ ||
      packet.event_type != FanyImePipeEventType::KeyEvent ||
      packet.request_id == FANY_IME_NO_REQUEST_ID ||
      (!packet.request_id && action.kind != KeyKind::LocalReset &&
       action.kind != KeyKind::Ignore) ||
      packet.pinyin_length < 0 || packet.pinyin_length >= 128)
    throw std::invalid_argument("Invalid Windows key request");
  nlohmann::json result;
  if (!input_enabled_) {
    result = {{"handled", false},
              {"commit", nullptr},
              {"diagnostic", nullptr},
              {"view", view()}};
    return {client_, epoch_, packet.request_id,
            action.kind != KeyKind::LocalReset &&
                action.kind != KeyKind::Ignore,
            std::move(result)};
  }
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  const auto digit_key = normalize_digit_key(packet.keycode);
  nlohmann::json current;
  if (modifiers <= 1 && digit_key >= '1' && digit_key <= '9')
    current = view();
  if (!current.is_null() && current.at("local_mode") != "unknown" &&
      ((current.at("local_mode") == "unicode" && modifiers == 1) ||
       (current.at("local_mode") != "unicode" && modifiers == 0))) {
    // TSF selects by VK digit, regardless of layout-produced text. Unicode
    // requires Shift; ordinary modes use unmodified digits. Use current IDs.
    const auto slot = static_cast<size_t>(digit_key - '1');
    const auto &page = current.at("candidates");
    if (slot < page.size()) {
      const auto &id = page.at(slot).at("id");
      result = select(epoch, id.at("generation").get<uint64_t>(),
                      id.at("index").get<size_t>());
    } else {
      result = {
          {"handled", !current.at("editing_text").get<std::string>().empty()},
          {"commit", nullptr},
          {"diagnostic", nullptr},
          {"view", current}};
    }
  } else if (action.kind == KeyKind::Ignore) {
    result = {{"handled", false},
              {"commit", nullptr},
              {"diagnostic", nullptr},
              {"view", view()}};
  } else if (action.kind == KeyKind::Character) {
    result = response(msime_client_character(
        session_, static_cast<uint8_t>(action.value), action.shift));
  } else {
    result = response(msime_client_command(session_, action.value));
    if (action.kind == KeyKind::CancelAndForward ||
        action.kind == KeyKind::LocalReset)
      result["handled"] = false;
  }
  return {client_, epoch_, packet.request_id,
          action.kind != KeyKind::LocalReset && action.kind != KeyKind::Ignore,
          std::move(result)};
}
std::optional<NavigationResult>
ServerSession::navigate(const FanyImeNamedpipeData &packet, uint64_t epoch,
                        const NavigationBindings &bindings) {
  check_active(epoch);
  if (packet.client_id != client_ ||
      packet.event_type != FanyImePipeEventType::KeyEvent ||
      !packet.request_id || packet.request_id == FANY_IME_NO_REQUEST_ID ||
      packet.pinyin_length < 0 || packet.pinyin_length >= 128)
    throw std::invalid_argument("Invalid Windows navigation request");
  if (!input_enabled_)
    return std::nullopt;
  // Do not fetch a full snapshot for keys that cannot use these bindings.
  auto action = navigation_action(packet, bindings, false);
  if (!action)
    return std::nullopt;
  const auto current = view();
  if (current.at("editing_text").get<std::string>().empty())
    return std::nullopt;
  action = navigation_action(packet, bindings,
                             current.at("local_mode") == "unicode");
  if (!action)
    return std::nullopt;
  auto result = action->command
                    ? response(msime_client_command(session_, *action->command))
                    : nlohmann::json{{"handled", true},
                                     {"commit", nullptr},
                                     {"diagnostic", nullptr},
                                     {"view", current}};
  return NavigationResult{
      {client_, epoch_, packet.request_id, true, std::move(result)},
      action->reply};
}
nlohmann::json ServerSession::select(uint64_t epoch, uint64_t generation,
                                     size_t index) {
  check_active(epoch);
  if (!input_enabled_)
    throw std::logic_error("Candidate selection while input disabled");
  return response(msime_client_select(session_, generation, index));
}
nlohmann::json ServerSession::update_preferences(uint64_t epoch,
                                                 const std::string &snapshot) {
  check_active(epoch);
  return response(msime_client_update_preferences(
      session_, reinterpret_cast<const uint8_t *>(snapshot.data()),
      snapshot.size()));
}
nlohmann::json ServerSession::view() const {
  check_thread();
  return response(msime_client_view(session_));
}
KeyResult ServerSession::punctuation(const FanyImeNamedpipeData &packet,
                                     uint64_t epoch) {
  check_active(epoch);
  const auto action = translate_key(packet);
  if (packet.client_id != client_ ||
      packet.event_type != FanyImePipeEventType::KeyEvent ||
      !packet.request_id || packet.request_id == FANY_IME_NO_REQUEST_ID ||
      packet.pinyin_length < 0 || packet.pinyin_length >= 128 ||
      action.kind != KeyKind::Character)
    throw std::invalid_argument("Invalid Windows punctuation request");
  if (!input_enabled_)
    return key(packet, epoch);
  auto result = response(
      msime_client_punctuation(session_, static_cast<uint8_t>(action.value)));
  return {client_, epoch_, packet.request_id, true, std::move(result)};
}
std::optional<WordCharacterResult>
ServerSession::word_character(const FanyImeNamedpipeData &packet,
                              uint64_t epoch, WordCharacterBinding binding) {
  check_active(epoch);
  const auto edge = word_character_edge(packet, binding);
  if (!edge)
    return std::nullopt;
  if (packet.client_id != client_ || !packet.request_id ||
      packet.request_id == FANY_IME_NO_REQUEST_ID || packet.pinyin_length < 0 ||
      packet.pinyin_length >= 128)
    throw std::invalid_argument("Invalid word-to-character request");
  if (!input_enabled_)
    return std::nullopt;
  const auto current = view();
  if (current.at("local_mode") == "unknown" ||
      current.at("editing_text").get<std::string>().empty())
    return std::nullopt;
  std::string fallback;
  for (const auto &candidate : current.at("candidates")) {
    if (!candidate.at("highlighted").get<bool>())
      continue;
    fallback = candidate.at("text").get<std::string>();
    const auto &id = candidate.at("id");
    auto selected = response(
        msime_client_select_edge(session_, id.at("generation").get<uint64_t>(),
                                 id.at("index").get<size_t>(), *edge));
    if (selected.at("handled").get<bool>())
      return WordCharacterResult{
          {client_, epoch_, packet.request_id, true, std::move(selected)},
          true};
    break;
  }
  // Legacy Normal delegates smart punctuation to TSF. Do not finish remaining
  // segments or translate punctuation here; only the highlighted text is sent.
  auto cancelled = response(msime_client_command(session_, MSIME_CANCEL));
  if (!cancelled.at("commit").is_null() ||
      !cancelled.at("view").at("editing_text").get<std::string>().empty())
    throw std::logic_error("Engine did not cancel word-to-character fallback");
  cancelled["handled"] = true;
  cancelled["commit"] = fallback;
  return WordCharacterResult{
      {client_, epoch_, packet.request_id, true, std::move(cancelled)}, false};
}
} // namespace msime::windows

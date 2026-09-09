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
  auto result = response(msime_client_focus(session_, true));
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
  const auto modifiers = packet.modifiers_down & ~FanyImePipeFlags::UiLess;
  nlohmann::json current;
  if (modifiers == 1 && packet.keycode >= '1' && packet.keycode <= '9')
    current = view();
  if (!current.is_null() && current.at("local_mode") == "unicode") {
    // TSF consumes Shift+1..9 as candidate selection in U mode even when the
    // keyboard layout translates that key to punctuation. Use the Engine's
    // actual mode and the shared page's candidate ID, not a raw-input prefix.
    const auto slot = static_cast<size_t>(packet.keycode - '1');
    const auto &page = current.at("candidates");
    if (slot < page.size()) {
      const auto &id = page.at(slot).at("id");
      result = select(epoch, id.at("generation").get<uint64_t>(),
                      id.at("index").get<size_t>());
    } else {
      result = {{"handled", true}, {"commit", nullptr},
                {"diagnostic", nullptr}, {"view", current}};
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
nlohmann::json ServerSession::select(uint64_t epoch, uint64_t generation,
                                     size_t index) {
  check_active(epoch);
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
} // namespace msime::windows

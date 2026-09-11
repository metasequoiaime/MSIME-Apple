#include "EngineSessionAdapter.h"
#include <nlohmann/json.hpp>
namespace msime::tsf {
using json = nlohmann::json;
EngineSessionAdapter::~EngineSessionAdapter() { destroy(); }
bool EngineSessionAdapter::response(char *raw, std::string *out,
                                    std::string *error) const {
  if (!raw) { if (error) *error = "Engine returned no response"; return false; }
  std::string text(raw); msime_client_string_free(raw);
  try {
    auto value = json::parse(text);
    if (!value.value("ok", false)) {
      if (error) {
        const auto code = value.value("error", "Engine request failed");
        *error = code.size() > 256 ? "Engine request failed" : code;
      }
      return false;
    }
    if (out) *out = std::move(text);
    return true;
  } catch (...) { if (error) *error = "Invalid Engine response"; return false; }
}
bool EngineSessionAdapter::create(const std::string &options, std::string *error) {
  destroy(); std::string result;
  if (!response(msime_client_create(reinterpret_cast<const uint8_t *>(options.data()), options.size()), &result, error)) return false;
  try {
    auto value = json::parse(result).at("value");
    session_ = value.is_object() ? value.at("session").get<uint64_t>() : value.get<uint64_t>();
    return session_ != 0;
  } catch (...) { if (error) *error = "Engine response has no valid session"; return false; }
}
void EngineSessionAdapter::destroy() noexcept {
  if (session_) { if (auto *raw = msime_client_destroy(session_)) msime_client_string_free(raw); session_ = 0; }
}
bool EngineSessionAdapter::character(uint8_t value, bool shift, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_character(session_, value, shift), out, error);
}
bool EngineSessionAdapter::command(uint32_t value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_command(session_, value), out, error);
}
bool EngineSessionAdapter::select(uint64_t generation, std::size_t index, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_select(session_, generation, index), out, error);
}
bool EngineSessionAdapter::select_edge(uint64_t generation, std::size_t index,
                                       uint8_t edge, std::string *out,
                                       std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_select_edge(session_, generation, index, edge), out, error);
}
bool EngineSessionAdapter::view(std::string *out, std::string *error) const {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_view(session_), out, error);
}
bool EngineSessionAdapter::punctuation(uint8_t value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_punctuation(session_, value), out, error);
}
bool EngineSessionAdapter::focus(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_focus(session_, value), out, error);
}
bool EngineSessionAdapter::chinese_punctuation(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_chinese_punctuation(session_, value), out, error);
}
bool EngineSessionAdapter::character_width(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_character_width(session_, value), out, error);
}
bool EngineSessionAdapter::english_mode(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_english_mode(session_, value), out, error);
}
bool EngineSessionAdapter::dedicated_english(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_english_mode(session_, value), out, error);
}
bool EngineSessionAdapter::paired_punctuation(bool value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_paired_punctuation(session_, value), out, error);
}
bool EngineSessionAdapter::punctuation_lock(uint8_t value, std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_set_punctuation_lock(session_, value), out, error);
}
bool EngineSessionAdapter::update_preferences(const std::string &snapshot,
                                              std::string *out, std::string *error) {
  if (!session_) { if (error) *error = "Engine session is not created"; return false; }
  return response(msime_client_update_preferences(
      session_, reinterpret_cast<const uint8_t *>(snapshot.data()), snapshot.size()), out, error);
}
}

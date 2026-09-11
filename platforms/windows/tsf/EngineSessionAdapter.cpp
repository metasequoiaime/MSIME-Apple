#include "EngineSessionAdapter.h"
#include <nlohmann/json.hpp>
namespace msime::tsf {
using json = nlohmann::json;
bool EngineSessionAdapter::parse_result(const std::string &text,
                                        EngineResult *out,
                                        std::string *error) {
  try {
    const auto root = json::parse(text);
    if (!root.value("ok", false)) {
      if (error) *error = "Engine request failed";
      return false;
    }
    const auto &value = root.at("value");
    EngineResult parsed;
    parsed.handled = value.value("handled", false);
    parsed.has_commit = value.value("has_commit", value.contains("commit"));
    if (value.contains("commit") && !value.at("commit").is_null())
      parsed.commit = value.at("commit").get<std::string>();
    parsed.diagnostic = value.value("diagnostic", "");
    if (value.contains("view")) {
      const auto &view = value.at("view");
      parsed.view.preedit = view.value("preedit", "");
      parsed.view.editing_text = view.value("editing_text", "");
      parsed.view.generation = view.value("generation", uint64_t{0});
      parsed.view.caret = view.value("caret", std::size_t{0});
      for (const auto &candidate : view.value("candidates", json::array())) {
        std::string id;
        if (candidate.contains("id")) {
          const auto &raw_id = candidate.at("id");
          id = raw_id.is_string() ? raw_id.get<std::string>() : raw_id.dump();
          if (parsed.view.generation == 0 && raw_id.is_object())
            parsed.view.generation = raw_id.value("generation", uint64_t{0});
        }
        parsed.view.candidates.push_back({std::move(id),
                                          candidate.value("text", "")});
      }
    }
    if (out) *out = std::move(parsed);
    return true;
  } catch (...) {
    if (error) *error = "Invalid Engine response";
    return false;
  }
}
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

#include "msime_client.h"
#include "../ChineseTextConversion.h"
#include <fcitx-utils/capabilityflags.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/utf8.h>
#include <fcitx-utils/event.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/action.h>
#include <fcitx/statusarea.h>
#include <fcitx/menu.h>
#include <fcitx/candidatelist.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/surroundingtext.h>
#include <fcitx/userinterface.h>
#include "../CandidateActionPolicy.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <optional>
#include <stdexcept>
#include <future>
#include <chrono>
#if __has_include(<fcitx/candidateaction.h>)
#include <fcitx/candidateaction.h>
#define MSIME_FCITX_ACTIONS 1
#endif

#ifndef MSIME_SYSTEM_OPTIONS
#define MSIME_SYSTEM_OPTIONS "/etc/msime-client/runtime-options.json"
#endif

namespace msime::fcitx_host {
using Json = nlohmann::json;
class FcitxEngine;
class FcitxMaintenanceAction;

// ABI buffers and errors never escape into diagnostics or the panel.
Json response(char *raw) {
  std::unique_ptr<char, decltype(&msime_client_string_free)> owned(raw, msime_client_string_free);
  if (!raw) throw std::runtime_error("MSIME request failed");
  auto value = Json::parse(raw);
  if (!value.value("ok", false)) throw std::runtime_error("MSIME request failed");
  return value.at("value");
}

Json readOptions() {
  std::filesystem::path path;
  if (const auto *overridePath = std::getenv("MSIME_FCITX5_OPTIONS")) {
    path = overridePath;
  } else {
    const auto *config = std::getenv("XDG_CONFIG_HOME");
    const auto *home = std::getenv("HOME");
    path = config && *config ? std::filesystem::path(config) :
           home && *home ? std::filesystem::path(home) / ".config" : std::filesystem::path();
    if (!path.is_absolute()) throw std::runtime_error("MSIME configuration unavailable");
    path /= "msime-client/runtime-options.json";
    if (!std::filesystem::exists(path) && !std::filesystem::is_symlink(path))
      path = MSIME_SYSTEM_OPTIONS;
  }
  if (!path.is_absolute()) throw std::runtime_error("MSIME configuration unavailable");
  std::ifstream file(path);
  std::array<char, 16385> data{};
  file.read(data.data(), data.size());
  if (file.bad() || file.gcount() <= 0 || file.gcount() >= static_cast<std::streamsize>(data.size()))
    throw std::runtime_error("MSIME configuration unavailable");
  return Json::parse(data.data(), data.data() + file.gcount());
}

std::string onlineSocket(const Json &options) {
  auto value = options.value("online_provider_socket", std::string{});
  if (value.empty()) {
    if (const auto *env = std::getenv("MSIME_ONLINE_PROVIDER_SOCKET")) value = env;
  }
  if (!value.empty()) return value;
  if (const auto *runtime = std::getenv("XDG_RUNTIME_DIR")) {
    const auto candidate = std::filesystem::path(runtime) / "msime-client" / "online.sock";
    std::error_code error;
    if (std::filesystem::is_socket(candidate, error)) return candidate.string();
  }
  return {};
}

class FcitxState : public fcitx::InputContextProperty {
public:
  explicit FcitxState(fcitx::InputContext &ic, FcitxEngine *engine, fcitx::EventLoop &loop)
      : ic_(ic), engine_(engine) {
    preferences_timer_ = loop.addTimeEvent(CLOCK_MONOTONIC, fcitx::now(CLOCK_MONOTONIC) + 250000,
        10000, [this](fcitx::EventSourceTime *timer, uint64_t) {
          refreshPreferences();
          refreshOnline();
          refreshTranslations();
          refreshClipboard();
          refreshCloudClipboard();
          refreshEmoji();
          refreshVoice();
          timer->setNextInterval(250000);
          timer->setOneShot();
          return true;
        });
  }
  ~FcitxState() override { close(); }
  void close() {
    if (session_) msime_client_string_free(msime_client_destroy(session_));
    session_ = 0;
    view_ = Json::object();
    preferences_ = Json::object();
    navigation_ = Json::object();
    options_path_.clear();
    resources_.clear();
    preferences_job_session_ = 0;
    preferences_snapshot_ = Json();
    online_socket_.clear();
    online_query_.clear();
    online_job_session_ = 0;
    ++online_epoch_;
    online_due_ = {};
    translation_query_.clear();
    translation_pending_.clear();
    translation_socket_.clear();
    clipboard_path_.clear();
    clipboard_items_.clear();
    clipboard_loading_ = false;
    clipboard_job_ = {};
    cloud_clipboard_socket_.clear();
    cloud_clipboard_items_.clear();
    cloud_clipboard_job_ = {};
    emoji_items_.clear();
    emoji_job_ = {};
    voice_socket_.clear();
    voice_job_ = {};
    voice_loading_ = false;
  }
  void clearPanel() {
    ic_.inputPanel().reset();
    ic_.updatePreedit();
    ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
  }
  bool restricted() const {
    return ic_.capabilityFlags().testAny(fcitx::CapabilityFlags{
      fcitx::CapabilityFlag::Password, fcitx::CapabilityFlag::Digit,
      fcitx::CapabilityFlag::Number, fcitx::CapabilityFlag::Dialable,
      fcitx::CapabilityFlag::Disable});
  }
  bool privateInput() const {
    return ic_.capabilityFlags().testAny(fcitx::CapabilityFlags{
      fcitx::CapabilityFlag::Sensitive, fcitx::CapabilityFlag::NoSpellCheck});
  }
  bool toggleEnglish() {
    if (!session_) return false;
    const bool enabled = !view_.value("dedicated_english", false);
    view_ = response(msime_client_set_english_mode(session_, enabled));
    render();
    return true;
  }
  bool toggleWidth() {
    if (!session_) return false;
    const auto width = view_.value("character_width", std::string("Halfwidth"));
    const bool fullwidth = !(width == "Fullwidth" || width == "fullwidth");
    view_ = response(msime_client_set_character_width(session_, fullwidth));
    render();
    return true;
  }
  bool selectEdge(uint8_t edge) {
    if (!session_ || view_.value("candidates", Json::array()).empty()) return false;
    for (const auto &candidate : view_.at("candidates")) {
      if (!candidate.value("highlighted", false)) continue;
      const auto &id = candidate.at("id");
      return apply(msime_client_select_edge(session_, id.at("generation"),
                                             id.at("index"), edge));
    }
    return false;
  }
  void maintenance(int operation);
  bool ensure() {
    if (!ic_.hasFocus() || restricted()) { close(); clearPanel(); return false; }
    if (session_ && private_ != privateInput()) { close(); clearPanel(); }
    if (session_) return true;
    auto options = readOptions();
    private_ = privateInput();
    preferences_ = options.value("preferences", Json::object());
    traditional_ = preferences_.value("traditional_chinese_output", false);
    navigation_ = preferences_.value("navigation", Json::object());
    const auto wordCharacter = preferences_.value("word_character", Json::object());
    word_character_enabled_ = wordCharacter.value("enabled", true);
    word_character_minus_equal_ = wordCharacter.value("keys", std::string("brackets")) == "minus_equal";
    options_path_ = options.value("preferences_directory", std::string());
    resources_ = options.value("resources", std::string());
    clipboard_path_ = options.value("preferences_directory", std::string());
    if (clipboard_path_.empty()) clipboard_path_ = options.value("clipboard_history_path", std::string());
    cloud_clipboard_socket_ = options.value("cloud_clipboard_provider_socket", std::string());
    if (cloud_clipboard_socket_.empty()) {
      if (const auto *socket = std::getenv("MSIME_CLOUD_CLIPBOARD_PROVIDER_SOCKET"))
        cloud_clipboard_socket_ = socket;
    }
    voice_socket_ = options.value("voice_provider_socket", std::string());
    if (voice_socket_.empty()) {
      if (const auto *socket = std::getenv("MSIME_VOICE_PROVIDER_SOCKET")) voice_socket_ = socket;
    }
    online_socket_ = onlineSocket(options);
    translation_socket_ = options.value("translation_provider_socket", std::string{});
    if (translation_socket_.empty()) {
      if (const auto *socket = std::getenv("MSIME_TRANSLATION_PROVIDER_SOCKET"))
        translation_socket_ = socket;
    }
    if (translation_socket_.empty()) translation_socket_ = online_socket_;
    if (private_) {
      preferences_["learning"] = false;
      preferences_["cloud_candidates"] = false;
      preferences_["ai_assistant"]["enabled"] = false;
      options["preferences"] = preferences_;
    }
    const auto document = options.dump();
    view_ = response(msime_client_create(reinterpret_cast<const uint8_t *>(document.data()), document.size()));
    session_ = view_.at("session").get<uint64_t>();
    view_ = response(msime_client_focus(session_, true)).at("view");
    return true;
  }
  void refreshPreferences() {
    try {
      if (preferences_job_.valid()) {
        if (preferences_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto snapshot = preferences_job_.get();
        if (session_ && session_ == preferences_job_session_ && ic_.hasFocus() &&
            !restricted() && private_ == privateInput() && !snapshot.is_null()) {
          if (private_) {
            snapshot["preferences"]["learning"] = false;
            snapshot["preferences"]["cloud_candidates"] = false;
            snapshot["preferences"]["ai_assistant"]["enabled"] = false;
          }
          if (snapshot != preferences_snapshot_) {
            const auto encoded = snapshot.dump();
            view_ = response(msime_client_update_preferences(session_,
                reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
            preferences_ = snapshot.at("preferences");
            traditional_ = preferences_.value("traditional_chinese_output", traditional_);
            navigation_ = preferences_.value("navigation", Json::object());
            const auto wordCharacter = preferences_.value("word_character", Json::object());
            word_character_enabled_ = wordCharacter.value("enabled", true);
            word_character_minus_equal_ = wordCharacter.value("keys", std::string("brackets")) == "minus_equal";
            preferences_snapshot_ = std::move(snapshot);
            render();
          }
        }
      }
      if (!session_ || options_path_.empty() || !ic_.hasFocus() || restricted()) return;
      preferences_job_session_ = session_;
      preferences_job_ = std::async(std::launch::async, [directory = options_path_] {
        return response(msime_client_try_load_preferences(
            reinterpret_cast<const uint8_t *>(directory.data()), directory.size()));
      }).share();
    } catch (...) {
      // Keep the active settings on malformed or concurrently written files.
    }
  }
  void refreshOnline() {
    try {
      for (uint8_t source = 0; source < 2; ++source) {
        auto &slot = online_slots_[source];
        if (!slot.job.valid() || slot.job.wait_for(std::chrono::seconds(0)) != std::future_status::ready)
          continue;
        auto result = slot.job.get();
        if (session_ && session_ == online_job_session_ && slot.epoch == online_epoch_ &&
            !privateInput() && ic_.hasFocus() && result.is_object() &&
            result.value("query", "") == slot.query) {
          Json candidates[2] = {Json::array(), Json::array()};
          for (const auto &item : result.value("candidates", Json::array())) {
            if (!item.is_object() || item.value("text", std::string{}).empty()) continue;
            const auto source = item.value("source", 255u);
            if (source < 2) candidates[source].push_back(item.at("text"));
          }
          for (uint8_t source = 0; source < 2; ++source) {
            if (candidates[source].empty()) continue;
            const auto encoded = candidates[source].dump();
            view_ = response(msime_client_apply_online_candidates(
                session_, reinterpret_cast<const uint8_t *>(slot.query.data()), slot.query.size(),
                reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size(), source)).at("view");
            render();
          }
        }
      }
      if (!session_ || online_socket_.empty() || privateInput() || !ic_.hasFocus() || restricted()) return;
      const auto query = response(msime_client_online_query(session_));
      if (!query.is_object()) return;
      const bool cloud = query.value("cloud_eligible", false) &&
                         query.value("cloud_candidates", true);
      const auto aiConfig = query.value("ai_assistant", Json::object());
      const bool ai = query.value("ai_eligible", false) &&
                      aiConfig.is_object() && aiConfig.value("enabled", false);
      if (!cloud && !ai) return;
      const auto encoded = query.dump();
      if (encoded != online_query_) {
        online_query_ = encoded;
        online_due_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
        return;
      }
      if (std::chrono::steady_clock::now() < online_due_) return;
      online_query_ = encoded;
      online_job_session_ = session_;
      for (uint8_t source = 0; source < 2; ++source) {
        const bool enabled = source == 0 ? cloud : ai;
        auto &slot = online_slots_[source];
        if (!enabled || slot.job.valid()) continue;
        auto providerQuery = query;
        if (source == 0) {
          providerQuery.erase("ai_assistant");
          providerQuery.erase("ai_context");
        } else {
          providerQuery["cloud_candidates"] = false;
        }
        const auto providerEncoded = providerQuery.dump();
        slot.query = encoded;
        slot.epoch = online_epoch_;
        slot.job = std::async(std::launch::async,
            [providerEncoded, encoded, socket = online_socket_] {
              auto raw = response(msime_client_online_provider_request(
                  reinterpret_cast<const uint8_t *>(providerEncoded.data()), providerEncoded.size(),
                  reinterpret_cast<const uint8_t *>(socket.data()), socket.size()));
              Json result = raw.is_object() ? raw : Json::object();
              result["query"] = encoded;
              return result;
            }).share();
      }
    } catch (...) {
      online_query_.clear();
    }
  }
  void startTranslation(const Json &query, bool offline, Json local = Json::array()) {
    const auto encoded = query.dump();
    translation_query_ = encoded;
    translation_session_ = session_;
    auto candidates = Json::array();
    for (const auto &candidate : view_.at("candidates"))
      candidates.push_back({{"text", candidate.at("text")}, {"source", candidate.at("source")}});
    const auto gloss = Json{{"generation", query.at("generation")},
                            {"user_data", query.value("user_data", Json())},
                            {"candidates", candidates}}.dump();
    const auto socket = preferences_.value("candidate_translations", false)
                            ? translation_socket_ : std::string{};
    translation_job_ = std::async(std::launch::async,
        [query, encoded, gloss, offline, local, socket, resources = resources_] () mutable {
          if (offline) {
            try {
              local = response(msime_client_candidate_gloss_request(
                  reinterpret_cast<const uint8_t *>(gloss.data()), gloss.size(),
                  reinterpret_cast<const uint8_t *>(resources.data()), resources.size()))
                  .value("translations", Json::array());
            } catch (...) {} // A missing local dictionary must not prevent online fallback.
          } else if (!socket.empty()) {
            auto transport = query;
            auto missing = Json::array();
            for (const auto &candidate : query.at("candidates")) {
              const auto &text = candidate.at("text");
              if (std::none_of(local.begin(), local.end(), [&](const Json &item) {
                    return item.at("text") == text;
                  })) missing.push_back(text);
            }
            transport["candidates"] = std::move(missing);
            if (!transport.at("candidates").empty()) {
              const auto request = transport.dump();
              try {
                auto result = response(msime_client_translation_provider_request(
                    reinterpret_cast<const uint8_t *>(request.data()), request.size(),
                    reinterpret_cast<const uint8_t *>(socket.data()), socket.size()));
                if (result.is_object())
                  for (const auto &item : result.value("translations", Json::array()))
                    local.push_back(item);
              } catch (...) {} // Retain local hits on provider failure.
            }
          }
          return Json{{"query", encoded}, {"translations", local},
                      {"continue_online", offline && !socket.empty()}};
        }).share();
  }
  void refreshTranslations() {
    try {
      const bool allowed = session_ && ic_.hasFocus() && !restricted() && !privateInput();
      const auto query = allowed ? response(msime_client_translation_query(session_)) : Json();
      const auto encodedQuery = query.is_object() ? query.dump() : std::string{};
      if (translation_job_.valid()) {
        if (translation_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = translation_job_.get();
        if (allowed && session_ == translation_session_ && query.is_object() &&
            result.is_object() && result.value("query", "") == encodedQuery) {
          const auto encoded = result.value("translations", Json::array()).dump();
          view_ = response(msime_client_apply_translations(
              session_, query.at("generation"), reinterpret_cast<const uint8_t *>(encoded.data()),
              encoded.size())).at("view");
          render();
          if (result.value("continue_online", false)) {
            startTranslation(query, false, result.at("translations"));
            return;
          }
        }
      }
      if (!query.is_object()) { translation_pending_.clear(); return; }
      if (encodedQuery == translation_query_) return;
      if (encodedQuery != translation_pending_) {
        translation_pending_ = encodedQuery;
        translation_due_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
        return;
      }
      if (std::chrono::steady_clock::now() < translation_due_) return;
      startTranslation(query, query.value("english_gloss", false));
    } catch (...) { /* Never expose candidate text or provider credentials in errors. */ }
  }
  void refreshClipboard() {
    try {
      if (clipboard_job_.valid()) {
        if (clipboard_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = clipboard_job_.get();
        clipboard_loading_ = false;
        if (session_ && ic_.hasFocus() && !restricted() && !privateInput() && result.is_object())
          clipboard_items_ = result.value("entries", Json::array());
      }
      if (clipboard_loading_ || clipboard_path_.empty() || restricted() || privateInput() || !ic_.hasFocus()) return;
      clipboard_loading_ = true;
      const auto path = clipboard_path_;
      clipboard_job_ = std::async(std::launch::async, [path] {
        auto raw = response(msime_client_load_clipboard_history(
            reinterpret_cast<const uint8_t *>(path.data()), path.size()));
        return raw.is_object() ? raw : Json::object();
      }).share();
    } catch (...) { clipboard_loading_ = false; clipboard_items_.clear(); }
  }
  bool pasteClipboard(size_t index = 0) {
    if (restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshClipboard();
    if (index >= clipboard_items_.size()) return false;
    const auto &item = clipboard_items_.at(index);
    const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
    if (text.empty()) return false;
    ic_.commitString(text);
    return true;
  }
  void refreshCloudClipboard() {
    try {
      if (cloud_clipboard_job_.valid()) {
        if (cloud_clipboard_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = cloud_clipboard_job_.get();
        if (ic_.hasFocus() && !restricted() && !privateInput() && result.is_object())
          cloud_clipboard_items_ = result.value("entries", Json::array());
      }
    } catch (...) { cloud_clipboard_items_.clear(); }
  }
  bool requestCloudClipboard() {
    if (cloud_clipboard_socket_.empty() || restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshCloudClipboard();
    if (!cloud_clipboard_items_.empty()) {
      const auto &item = cloud_clipboard_items_.front();
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) { ic_.commitString(text); return true; }
    }
    if (cloud_clipboard_job_.valid()) return false;
    const auto socket = cloud_clipboard_socket_;
    cloud_clipboard_job_ = std::async(std::launch::async, [socket] {
      const auto request = Json{{"operation", "list"}, {"search", ""}}.dump();
      auto raw = response(msime_client_cloud_clipboard_provider_request(
          reinterpret_cast<const uint8_t *>(request.data()), request.size(),
          reinterpret_cast<const uint8_t *>(socket.data()), socket.size()));
      return raw.is_object() ? raw : Json::object();
    }).share();
    return false;
  }
  void refreshEmoji() {
    try {
      if (emoji_job_.valid()) {
        if (emoji_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = emoji_job_.get();
        if (ic_.hasFocus() && !restricted() && !privateInput() && result.is_object())
          emoji_items_ = result.value("items", Json::array());
      }
    } catch (...) { emoji_items_.clear(); }
  }
  bool insertEmoji() {
    if (restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshEmoji();
    if (!emoji_items_.empty()) {
      const auto &item = emoji_items_.front();
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) { ic_.commitString(text); return true; }
    }
    if (emoji_job_.valid() || resources_.empty()) return false;
    const auto resources = resources_;
    emoji_job_ = std::async(std::launch::async, [resources] {
      const auto query = Json{{"limit", 5}, {"cursor", true}}.dump();
      auto result = response(msime_client_emoji_catalog_request(
          reinterpret_cast<const uint8_t *>(query.data()), query.size(),
          reinterpret_cast<const uint8_t *>(resources.data()), resources.size()));
      return result.is_object() ? result : Json::object();
    }).share();
    return false;
  }
  bool refreshVoice() {
    try {
      if (!voice_job_.valid()) return false;
      if (voice_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return false;
      auto result = voice_job_.get();
      voice_loading_ = false;
      if (session_ && ic_.hasFocus() && !restricted() && !privateInput() && result.is_object()) {
        const auto text = result.value("text", std::string{});
        if (!text.empty()) { ic_.commitString(text); return true; }
      }
    } catch (...) { voice_loading_ = false; }
    return false;
  }
  bool requestVoice() {
    if (voice_socket_.empty() || restricted() || privateInput() || !ic_.hasFocus() || voice_loading_) return false;
    if (refreshVoice()) return true;
    if (voice_loading_) return false;
    voice_loading_ = true;
    const auto socket = voice_socket_;
    const auto generation = view_.value("generation", uint64_t{});
    voice_job_ = std::async(std::launch::async, [socket, generation] {
      const auto query = Json{{"language", "zh-cn"}, {"generation", generation}}.dump();
      auto result = response(msime_client_voice_provider_request(
          reinterpret_cast<const uint8_t *>(query.data()), query.size(),
          reinterpret_cast<const uint8_t *>(socket.data()), socket.size()));
      return result.is_object() ? result : Json::object();
    }).share();
    return true;
  }
  bool apply(char *raw) {
    auto result = response(raw);
    if (result.contains("commit") && result["commit"].is_string()) {
      auto text = result["commit"].get<std::string>();
      if (traditional_ && view_.value("scheme", 0u) != 3)
        text = msime_linux_simplified_to_traditional(text);
      ic_.commitString(text);
    }
    view_ = result.contains("view") ? result.at("view") : result;
    render();
    return result.value("handled", false);
  }
  bool command(uint32_t command) { return apply(msime_client_command(session_, command)); }
  bool punctuation(uint8_t value) {
    uint32_t preceding = 0;
    const auto &surrounding = ic_.surroundingText();
    if (!privateInput() && ic_.capabilityFlags().test(fcitx::CapabilityFlag::SurroundingText) &&
        surrounding.isValid() && surrounding.cursor() > 0 &&
        surrounding.cursor() == surrounding.anchor()) {
      const auto &text = surrounding.text();
      const auto length = fcitx::utf8::lengthValidated(text);
      if (length != fcitx::utf8::INVALID_LENGTH && surrounding.cursor() <= length)
        preceding = fcitx::utf8::getChar(
            fcitx::utf8::nextNChar(text.begin(), surrounding.cursor() - 1), text.end());
    }
    return apply(msime_client_punctuation_with_context(session_, value, preceding));
  }
  void select(uint64_t session, uint64_t generation, size_t index) {
    if (!ensure() || session_ != session || view_.value("generation", uint64_t{}) != generation) return;
    apply(msime_client_select(session_, generation, index));
  }
  void render();
  bool toggleTraditional() {
    if (!session_ || view_.value("scheme", 0u) == 3) return false;
    traditional_ = !traditional_;
    render();
    return true;
  }
  bool key(fcitx::KeyEvent &event);
  uint64_t session_ = 0;
  Json view_ = Json::object();
  Json preferences_ = Json::object();
  Json navigation_ = Json::object();
  std::string options_path_;
  std::string resources_;
  Json preferences_snapshot_;
  uint64_t preferences_job_session_ = 0;
  std::shared_future<Json> preferences_job_;
  std::unique_ptr<fcitx::EventSourceTime> preferences_timer_;
  fcitx::InputContext &ic_;
  FcitxEngine *engine_;
  bool private_ = false;
  bool traditional_ = false;
  std::string online_socket_, online_query_;
  uint64_t online_job_session_ = 0;
  struct OnlineSlot {
    std::shared_future<Json> job;
    std::string query;
    uint64_t epoch = 0;
  } online_slots_[2];
  uint64_t online_epoch_ = 0;
  std::chrono::steady_clock::time_point online_due_{};
  std::string translation_query_, translation_pending_, translation_socket_;
  std::chrono::steady_clock::time_point translation_due_{};
  uint64_t translation_session_ = 0;
  std::shared_future<Json> translation_job_;
  std::string clipboard_path_;
  Json clipboard_items_ = Json::array();
  bool clipboard_loading_ = false;
  std::shared_future<Json> clipboard_job_;
  std::string cloud_clipboard_socket_;
  Json cloud_clipboard_items_ = Json::array();
  std::shared_future<Json> cloud_clipboard_job_;
  Json emoji_items_ = Json::array();
  std::shared_future<Json> emoji_job_;
  std::string voice_socket_;
  std::shared_future<Json> voice_job_;
  bool voice_loading_ = false;
  bool word_character_enabled_ = true;
  bool word_character_minus_equal_ = false;
};

class FcitxCandidate : public fcitx::CandidateWord {
public:
  FcitxCandidate(fcitx::FactoryFor<FcitxState> *factory, const Json &candidate, bool traditional)
      : CandidateWord(fcitx::Text((traditional ? msime_linux_simplified_to_traditional(candidate.at("text").get<std::string>())
                                               : candidate.at("text").get<std::string>()) +
          (candidate.value("annotation", std::string()).empty() ? "" :
           "  " + candidate.at("annotation").get<std::string>()) +
          (candidate.contains("translation") && candidate.at("translation").is_string()
              ? "  " + candidate.at("translation").get<std::string>() : ""))), factory_(factory),
        session_(candidate.at("id").at("session")), generation_(candidate.at("id").at("generation")),
        index_(candidate.at("id").at("index")) {}
  void select(fcitx::InputContext *ic) const override {
    try { ic->propertyFor(factory_)->select(session_, generation_, index_); } catch (...) {}
  }
  uint64_t session() const { return session_; }
  uint64_t generation() const { return generation_; }
  size_t index() const { return index_; }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  uint64_t session_, generation_;
  size_t index_;
};

// The runtime already pages candidates. Never page its current page a second time.
class FcitxPage : public fcitx::CandidateList,
                  public fcitx::PageableCandidateList
#ifdef MSIME_FCITX_ACTIONS
                  , public fcitx::ActionableCandidateList
#endif
{
public:
  FcitxPage(FcitxState &state, fcitx::FactoryFor<FcitxState> *factory) : state_(state),
      session_(state.session_), generation_(state.view_.at("generation")),
      page_(state.view_.at("page")), pages_(state.view_.at("page_count")),
      layout_(state.preferences_.value("candidate_layout", std::string("vertical")) == "horizontal"
          ? fcitx::CandidateLayoutHint::Horizontal : fcitx::CandidateLayoutHint::Vertical) {
    setPageable(this);
#ifdef MSIME_FCITX_ACTIONS
    setActionable(this);
#endif
    for (const auto &candidate : state.view_.at("candidates")) {
      if (candidate.value("highlighted", false)) cursor_ = words_.size();
      words_.push_back(std::make_unique<FcitxCandidate>(factory, candidate, state.traditional_));
      labels_.emplace_back(std::to_string(words_.size()) + ". ");
    }
  }
  const fcitx::Text &label(int index) const override { return labels_.at(index); }
  const fcitx::CandidateWord &candidate(int index) const override { return *words_.at(index); }
  int size() const override { return words_.size(); }
  int cursorIndex() const override { return cursor_; }
  fcitx::CandidateLayoutHint layoutHint() const override { return layout_; }
  bool hasPrev() const override { return page_ > 0; }
  bool hasNext() const override { return page_ + 1 < pages_; }
  bool usedNextBefore() const override { return page_ > 0; }
  int totalPages() const override { return pages_; }
  int currentPage() const override { return page_; }
  void prev() override { move(MSIME_PREVIOUS_PAGE); }
  void next() override { move(MSIME_NEXT_PAGE); }
#ifdef MSIME_FCITX_ACTIONS
  bool hasAction(const fcitx::CandidateWord &candidate) const override {
    return dynamic_cast<const FcitxCandidate *>(&candidate) != nullptr;
  }
  std::vector<fcitx::CandidateAction>
  candidateActions(const fcitx::CandidateWord &candidate) const override {
    std::vector<fcitx::CandidateAction> actions;
    const auto *item = dynamic_cast<const FcitxCandidate *>(&candidate);
    if (!item) return actions;
    if (state_.session_ != item->session() ||
        state_.view_.value("generation", uint64_t{}) != item->generation()) return actions;
    const auto make = [](int id, const char *text) {
      fcitx::CandidateAction action;
      action.setId(id);
      action.setText(text);
      return action;
    };
    actions.push_back(make(1, "固定候选"));
    const auto candidates = state_.view_.value("candidates", Json::array());
    const auto candidateIt = std::find_if(candidates.begin(), candidates.end(),
        [&](const Json &candidate) {
          return candidate.value("id", Json::object()).value("index", size_t(-1)) == item->index();
        });
    if (candidateIt == candidates.end()) return actions;
    const auto &candidateJson = *candidateIt;
    const auto source = candidateJson.value("source", 0u);
    if (msime::linux_host::candidate_dictionary_removal_available(
            state_.view_.value("scheme", 0u), source,
            candidateJson.value("text", std::string{})))
      actions.push_back(make(2, "删除候选"));
    for (int slot = 1; slot <= 5; ++slot)
      actions.push_back(make(10 + slot, ("固定到 " + std::to_string(slot)).c_str()));
    actions.push_back(make(20, "取消固定"));
    return actions;
  }
  void triggerAction(const fcitx::CandidateWord &candidate, int action) override {
    const auto *item = dynamic_cast<const FcitxCandidate *>(&candidate);
    if (!item) return;
    // ensure() can clear the panel and destroy this page and its candidate.
    auto *state = &state_;
    const auto session = item->session();
    const auto generation = item->generation();
    const auto index = item->index();
    const auto actions = candidateActions(candidate);
    if (std::none_of(actions.begin(), actions.end(),
        [action](const auto &available) { return available.id() == action; })) return;
    try {
      if (!state->ensure() || state->session_ != session ||
          state->view_.value("generation", uint64_t{}) != generation) return;
      char *raw = nullptr;
      if (action == 1) raw = msime_client_pin_candidate(session, generation, index);
      else if (action == 2) raw = msime_client_remove_candidate(session, generation, index);
      else if (action >= 11 && action <= 15)
        raw = msime_client_fix_candidate_position(session, generation, index, static_cast<uint8_t>(action - 10));
      else if (action == 20) raw = msime_client_clear_candidate_position(session, generation, index);
      if (raw) state->apply(raw);
    } catch (...) {}
  }
#endif
private:
  void move(uint32_t command) {
    // render() replaces this list. Do not access members after dispatch.
    auto *state = &state_;
    const auto session = session_;
    const auto generation = generation_;
    try {
      if (state->ensure() && state->session_ == session &&
          state->view_.value("generation", uint64_t{}) == generation)
        state->command(command);
    } catch (...) {}
  }
  FcitxState &state_;
  uint64_t session_, generation_;
  int page_, pages_, cursor_ = -1;
  fcitx::CandidateLayoutHint layout_;
  std::vector<std::unique_ptr<FcitxCandidate>> words_;
  std::vector<fcitx::Text> labels_;
};

// Status actions are shared by the addon, but their values belong to the
// supplied context. Never cache one application's checked state globally.
class FcitxModeAction : public fcitx::Action {
public:
  enum class Mode { EnglishCandidates, Fullwidth };
  FcitxModeAction(fcitx::FactoryFor<FcitxState> *factory, Mode mode)
      : factory_(factory), mode_(mode) { setCheckable(true); }
  std::string shortText(fcitx::InputContext *) const override {
    return mode_ == Mode::EnglishCandidates ? "英文候选" : "全角";
  }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    if (!state->session_) return false;
    return mode_ == Mode::EnglishCandidates
        ? state->view_.value("dedicated_english", false)
        : state->view_.value("character_width", std::string{}) == "Fullwidth";
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted()) return;
    try {
      if (!state->ensure()) return;
      if (!state->view_.value("editing_text", std::string{}).empty())
        state->command(MSIME_COMMIT_RAW);
      if (mode_ == Mode::EnglishCandidates) state->toggleEnglish();
      else state->toggleWidth();
      update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  Mode mode_;
};

class FcitxMaintenanceAction : public fcitx::SimpleAction {
public:
  FcitxMaintenanceAction(fcitx::FactoryFor<FcitxState> *factory, int operation,
                         const char *text)
      : factory_(factory), operation_(operation) {
    setShortText(text);
    setLongText(text);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->maintenance(operation_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  int operation_;
};

class FcitxClipboardAction : public fcitx::SimpleAction {
public:
  explicit FcitxClipboardAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("剪贴板");
    setLongText("插入最近的剪贴板历史");
  }
  void setMenu(fcitx::Menu *menu) { fcitx::SimpleAction::setMenu(menu); }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->pasteClipboard(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxClipboardItemAction : public fcitx::SimpleAction {
public:
  FcitxClipboardItemAction(fcitx::FactoryFor<FcitxState> *factory, size_t index)
      : factory_(factory), index_(index) { setLabel("剪贴板 " + std::to_string(index + 1)); }
  std::string shortText(fcitx::InputContext *ic) const override {
    if (ic) {
      const auto *state = ic->propertyFor(factory_);
      if (index_ < state->clipboard_items_.size()) {
        const auto &item = state->clipboard_items_.at(index_);
        const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
        if (!text.empty()) {
          const auto clipped = text.substr(0, 40);
          return clipped + (text.size() > clipped.size() ? "…" : "");
        }
      }
    }
    return "剪贴板 " + std::to_string(index_ + 1);
  }
  void setLabel(const std::string &label) { setShortText(label); setLongText(label); }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->pasteClipboard(index_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  size_t index_;
};

class FcitxCloudClipboardAction : public fcitx::SimpleAction {
public:
  explicit FcitxCloudClipboardAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("云剪贴板");
    setLongText("读取云剪贴板最近条目");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->requestCloudClipboard(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxEmojiAction : public fcitx::SimpleAction {
public:
  explicit FcitxEmojiAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("表情");
    setLongText("插入本地表情目录中的第一项");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->insertEmoji(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxVoiceAction : public fcitx::SimpleAction {
public:
  explicit FcitxVoiceAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("语音");
    setLongText("请求用户语音服务并插入识别文本");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->requestVoice(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxTraditionalAction : public fcitx::Action {
public:
  explicit FcitxTraditionalAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "繁体"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->view_.value("scheme", 0u) != 3 && state->traditional_;
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->toggleTraditional()) update(ic);
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

// Each context owns a thread-bound Host API session. Fcitx never copies composing state.
class FcitxEngine : public fcitx::InputMethodEngine {
public:
  explicit FcitxEngine(fcitx::Instance *instance) : instance_(instance) {
    instance->inputContextManager().registerProperty("msimeState", &factory_);
    english_action_.registerAction("msime-english-candidates", &instance->userInterfaceManager());
    width_action_.registerAction("msime-fullwidth", &instance->userInterfaceManager());
    maintenance_action_.registerAction("msime-candidate-tools", &instance->userInterfaceManager());
    clipboard_action_.registerAction("msime-clipboard", &instance->userInterfaceManager());
    cloud_clipboard_action_.registerAction("msime-cloud-clipboard", &instance->userInterfaceManager());
    emoji_action_.registerAction("msime-emoji", &instance->userInterfaceManager());
    voice_action_.registerAction("msime-voice", &instance->userInterfaceManager());
    traditional_action_.registerAction("msime-traditional", &instance->userInterfaceManager());
    clipboard_action_.setMenu(&clipboard_menu_);
    clipboard_menu_.addAction(&clipboard_item1_);
    clipboard_menu_.addAction(&clipboard_item2_);
    clipboard_menu_.addAction(&clipboard_item3_);
    clipboard_menu_.addAction(&clipboard_item4_);
    clipboard_menu_.addAction(&clipboard_item5_);
    maintenance_action_.setMenu(&maintenance_menu_);
    maintenance_menu_.addAction(&pin_action_);
    maintenance_menu_.addAction(&remove_action_);
    maintenance_menu_.addAction(&fix1_action_);
    maintenance_menu_.addAction(&fix2_action_);
    maintenance_menu_.addAction(&fix3_action_);
    maintenance_menu_.addAction(&fix4_action_);
    maintenance_menu_.addAction(&fix5_action_);
    maintenance_menu_.addAction(&clear_action_);
    capability_watch_ = instance->watchEvent(
        fcitx::EventType::InputContextCapabilityChanged,
        fcitx::EventWatcherPhase::PreInputMethod, [this](fcitx::Event &event) {
          auto *ic = static_cast<fcitx::InputContextEvent &>(event).inputContext();
          auto *state = ic->propertyFor(&factory_);
          // Never activate MSIME or clear another input method's panel here.
          if (!state->session_) return;
          if (state->restricted() || state->private_ != state->privateInput()) {
            state->close();
            state->clearPanel();
          } else {
            // Client-side preedit support may also change while composing.
            try { state->render(); } catch (...) { unavailable(*state); }
          }
        });
    focus_watch_ = instance->watchEvent(
        fcitx::EventType::InputContextFocusOut,
        fcitx::EventWatcherPhase::PreInputMethod, [this](fcitx::Event &event) {
          auto *ic = static_cast<fcitx::InputContextEvent &>(event).inputContext();
          auto *state = ic->propertyFor(&factory_);
          if (!state->session_) return;
          state->close();
          state->clearPanel();
        });
  }
  void activate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &english_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &width_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &maintenance_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &clipboard_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &cloud_clipboard_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &emoji_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &voice_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &traditional_action_);
    try { if (state->ensure()) state->render(); } catch (...) { unavailable(*state); }
  }
  void deactivate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    event.inputContext()->statusArea().removeAction(&english_action_);
    event.inputContext()->statusArea().removeAction(&width_action_);
    event.inputContext()->statusArea().removeAction(&maintenance_action_);
    event.inputContext()->statusArea().removeAction(&clipboard_action_);
    event.inputContext()->statusArea().removeAction(&cloud_clipboard_action_);
    event.inputContext()->statusArea().removeAction(&emoji_action_);
    event.inputContext()->statusArea().removeAction(&voice_action_);
    event.inputContext()->statusArea().removeAction(&traditional_action_);
    state->close(); state->clearPanel();
  }
  void reset(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    try { if (state->session_) state->command(MSIME_CANCEL); } catch (...) { state->close(); }
    state->clearPanel();
  }
  void keyEvent(const fcitx::InputMethodEntry &, fcitx::KeyEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    try { if (state->ensure() && state->key(event)) event.filterAndAccept(); }
    catch (...) { unavailable(*state); }
  }
  static void unavailable(FcitxState &state) {
    state.close(); state.clearPanel();
    state.ic_.inputPanel().setAuxUp(fcitx::Text("MSIME：请检查运行配置"));
    state.ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
  }
  fcitx::Instance *instance_;
  fcitx::FactoryFor<FcitxState> factory_{[this](fcitx::InputContext &ic) {
    return new FcitxState(ic, this, instance_->eventLoop());
  }};
  std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> capability_watch_;
  std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>> focus_watch_;
  FcitxModeAction english_action_{&factory_, FcitxModeAction::Mode::EnglishCandidates};
  FcitxModeAction width_action_{&factory_, FcitxModeAction::Mode::Fullwidth};
  fcitx::Menu maintenance_menu_;
  FcitxMaintenanceAction maintenance_action_{&factory_, 0, "候选维护"};
  FcitxClipboardAction clipboard_action_{&factory_};
  FcitxCloudClipboardAction cloud_clipboard_action_{&factory_};
  FcitxEmojiAction emoji_action_{&factory_};
  FcitxVoiceAction voice_action_{&factory_};
  FcitxTraditionalAction traditional_action_{&factory_};
  fcitx::Menu clipboard_menu_;
  FcitxClipboardItemAction clipboard_item1_{&factory_, 0};
  FcitxClipboardItemAction clipboard_item2_{&factory_, 1};
  FcitxClipboardItemAction clipboard_item3_{&factory_, 2};
  FcitxClipboardItemAction clipboard_item4_{&factory_, 3};
  FcitxClipboardItemAction clipboard_item5_{&factory_, 4};
  FcitxMaintenanceAction pin_action_{&factory_, 1, "固定候选"};
  FcitxMaintenanceAction remove_action_{&factory_, 2, "删除候选"};
  FcitxMaintenanceAction fix1_action_{&factory_, 11, "固定到 1"};
  FcitxMaintenanceAction fix2_action_{&factory_, 12, "固定到 2"};
  FcitxMaintenanceAction fix3_action_{&factory_, 13, "固定到 3"};
  FcitxMaintenanceAction fix4_action_{&factory_, 14, "固定到 4"};
  FcitxMaintenanceAction fix5_action_{&factory_, 15, "固定到 5"};
  FcitxMaintenanceAction clear_action_{&factory_, 20, "取消固定"};
};

void FcitxState::render() {
  if (engine_) {
    engine_->english_action_.update(&ic_);
    engine_->width_action_.update(&ic_);
  }
  ic_.inputPanel().reset();
  const auto editing = view_.value("editing_text", std::string());
  fcitx::Text preedit(editing, fcitx::TextFormatFlag::Underline);
  preedit.setCursor(std::min(editing.size(), view_.value("caret_position", size_t{})));
  if (ic_.capabilityFlags().test(fcitx::CapabilityFlag::Preedit))
    ic_.inputPanel().setClientPreedit(preedit);
  else ic_.inputPanel().setPreedit(preedit);
  if (!view_.at("candidates").empty()) {
    // Look up the registered factory via the owning engine for stable candidate callbacks.
    if (engine_) ic_.inputPanel().setCandidateList(std::make_unique<FcitxPage>(*this, &engine_->factory_));
    ic_.inputPanel().setAuxDown(fcitx::Text(std::to_string(view_.at("page").get<int>() + 1) +
        "/" + std::to_string(view_.at("page_count").get<int>())));
  }
  ic_.updatePreedit();
  ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

void FcitxState::maintenance(int operation) {
  if (!ensure() || view_.value("candidates", Json::array()).empty()) return;
  for (const auto &candidate : view_.at("candidates")) {
    if (!candidate.value("highlighted", false)) continue;
    const auto &id = candidate.at("id");
    const auto generation = id.at("generation").get<uint64_t>();
    const auto index = id.at("index").get<size_t>();
    char *raw = nullptr;
    if (operation == 1) raw = msime_client_pin_candidate(session_, generation, index);
    else if (operation == 2 && msime::linux_host::candidate_dictionary_removal_available(
                 view_.value("scheme", 0u), candidate.value("source", 0u),
                 candidate.value("text", std::string{})))
      raw = msime_client_remove_candidate(session_, generation, index);
    else if (operation >= 11 && operation <= 15)
      raw = msime_client_fix_candidate_position(session_, generation, index,
                                                 static_cast<uint8_t>(operation - 10));
    else if (operation == 20)
      raw = msime_client_clear_candidate_position(session_, generation, index);
    if (raw) apply(raw);
    return;
  }
}

bool FcitxState::key(fcitx::KeyEvent &event) {
  const auto &key = event.key();
  if (event.isRelease() || key.isModifier()) return false;
  const bool composing = !view_.value("editing_text", std::string()).empty();
  const auto sym = key.sym();
  const auto states = key.states();
  const bool ctrl = states.test(fcitx::KeyState::Ctrl);
  const bool alt = states.test(fcitx::KeyState::Alt);
  const bool shift = states.test(fcitx::KeyState::Shift);
  if (ctrl && shift && !alt && (sym == FcitxKey_e || sym == FcitxKey_E)) {
    if (composing) command(MSIME_COMMIT_RAW);
    return toggleEnglish();
  }
  if (sym == FcitxKey_space && ctrl && shift && !alt) {
    if (composing) command(MSIME_COMMIT_RAW);
    return toggleWidth();
  }
  if (states.testAny(fcitx::KeyStates{fcitx::KeyState::Ctrl, fcitx::KeyState::Alt,
                                      fcitx::KeyState::Super, fcitx::KeyState::Hyper})) {
    if (composing) command(MSIME_CANCEL);
    return false;
  }
  // CapsLock uppercase letters belong to the editor when a new composition
  // has not started, matching the Windows and IBus host routers.
  if (states.test(fcitx::KeyState::CapsLock) && !shift &&
      sym >= FcitxKey_A && sym <= FcitxKey_Z &&
      view_.value("editing_text", std::string{}).empty() &&
      view_.value("candidates", Json::array()).empty())
    return false;
  if (composing) {
    const bool japanese = view_.value("scheme", 0u) == 3;
    if (!shift && !view_.at("candidates").empty()) {
      if (word_character_enabled_ && !japanese &&
          ((word_character_minus_equal_ && sym == FcitxKey_minus) ||
           (!word_character_minus_equal_ && sym == FcitxKey_bracketleft)))
        return selectEdge(MSIME_FIRST_HAN);
      if (word_character_enabled_ && !japanese &&
          ((word_character_minus_equal_ && sym == FcitxKey_equal) ||
           (!word_character_minus_equal_ && sym == FcitxKey_bracketright)))
        return selectEdge(MSIME_LAST_HAN);
      if ((sym == FcitxKey_minus && !japanese && navigation_.value("minus_equal", true)) ||
          (sym == FcitxKey_comma && navigation_.value("comma_period", true)) ||
          (sym == FcitxKey_bracketleft && navigation_.value("brackets", false)))
        return command(MSIME_PREVIOUS_PAGE);
      if ((sym == FcitxKey_equal && !japanese && navigation_.value("minus_equal", true)) ||
          (sym == FcitxKey_period && navigation_.value("comma_period", true)) ||
          (sym == FcitxKey_bracketright && navigation_.value("brackets", false)))
        return command(MSIME_NEXT_PAGE);
    }
    switch (sym) {
    case FcitxKey_Escape: return command(MSIME_CANCEL);
    case FcitxKey_BackSpace: return command(MSIME_BACKSPACE);
    case FcitxKey_Delete: case FcitxKey_KP_Delete: return command(MSIME_DELETE_FORWARD);
    case FcitxKey_Return: case FcitxKey_KP_Enter: return command(MSIME_COMMIT_RAW);
    case FcitxKey_space: return command(MSIME_COMMIT_CANDIDATE);
    case FcitxKey_Left: case FcitxKey_KP_Left: return command(MSIME_MOVE_LEFT);
    case FcitxKey_Right: case FcitxKey_KP_Right: return command(MSIME_MOVE_RIGHT);
    case FcitxKey_Home: case FcitxKey_KP_Home:
      return command(MSIME_FIRST_CANDIDATE_ON_PAGE);
    case FcitxKey_End: case FcitxKey_KP_End:
      return command(MSIME_LAST_CANDIDATE_ON_PAGE);
    case FcitxKey_Tab: case FcitxKey_KP_Tab:
      if (navigation_.value("tab", true)) return command(shift ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE);
      break;
    case FcitxKey_ISO_Left_Tab:
      if (navigation_.value("tab", true)) return command(MSIME_PREVIOUS_PAGE);
      break;
    case FcitxKey_Page_Up: case FcitxKey_KP_Page_Up:
      if (navigation_.value("page_up_down", true)) return command(MSIME_PREVIOUS_PAGE);
      break;
    case FcitxKey_Page_Down: case FcitxKey_KP_Page_Down:
      if (navigation_.value("page_up_down", true)) return command(MSIME_NEXT_PAGE);
      break;
    case FcitxKey_Up: case FcitxKey_KP_Up:
      if (navigation_.value("candidate_arrow_navigation", navigation_.value("arrows", true)))
        return command(MSIME_PREVIOUS_CANDIDATE);
      break;
    case FcitxKey_Down: case FcitxKey_KP_Down:
      if (navigation_.value("candidate_arrow_navigation", navigation_.value("arrows", true)))
        return command(MSIME_NEXT_CANDIDATE);
      break;
    default: break;
    }
    const auto number = [&]() -> std::optional<size_t> {
      if (sym >= FcitxKey_1 && sym <= FcitxKey_9)
        return static_cast<size_t>(sym - FcitxKey_1);
      if (sym >= FcitxKey_KP_1 && sym <= FcitxKey_KP_9)
        return static_cast<size_t>(sym - FcitxKey_KP_1);
      return std::nullopt;
    }();
    if (number && !shift &&
        view_.value("local_mode", std::string("none")) != "unicode" &&
        !view_.value("nine_key", false) &&
        preferences_.value("number_row_selection", true)) {
      const size_t index = *number;
      if (index < view_.at("candidates").size()) {
        const auto id = view_.at("candidates").at(index).at("id");
        return apply(msime_client_select(session_, id.at("generation"), id.at("index")));
      }
      return false;
    }
  }
  const auto text = fcitx::Key::keySymToUTF8(sym);
  if (text.size() == 1 && text[0] >= 0x20 && text[0] <= 0x7e) {
    if (text[0] == ';' && !shift && view_.value("microsoft_shuangpin", false)) {
      const auto editing = view_.value("editing_text", std::string{});
      const auto caret = std::min(editing.size(), view_.value("caret_position", editing.size()));
      const auto separator = caret ? editing.rfind('\'', caret - 1) : std::string::npos;
      const auto start = separator == std::string::npos ? 0 : separator + 1;
      if ((caret - start) % 2 == 1)
        return apply(msime_client_character(session_, ';', false));
    }
    if (text[0] == ',' || text[0] == '.' || text[0] == ';' || text[0] == ':' ||
        text[0] == '!' || text[0] == '?' || text[0] == '(' || text[0] == ')' ||
        text[0] == '[' || text[0] == ']' || text[0] == '{' || text[0] == '}')
      return punctuation(static_cast<uint8_t>(text[0]));
    return apply(msime_client_character(session_, static_cast<uint8_t>(text[0]), key.states().test(fcitx::KeyState::Shift)));
  }
  if (composing) command(MSIME_FINISH_COMPOSITION);
  return false;
}

class FcitxFactory : public fcitx::AddonFactory {
public:
  fcitx::AddonInstance *create(fcitx::AddonManager *manager) override { return new FcitxEngine(manager->instance()); }
};
} // namespace msime::fcitx_host

FCITX_ADDON_FACTORY(msime::fcitx_host::FcitxFactory)

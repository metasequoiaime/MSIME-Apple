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
#include <cmath>
#include <spawn.h>
#include <vector>
#include <cstring>
#include <mutex>
#if __has_include(<fcitx/candidateaction.h>)
#include <fcitx/candidateaction.h>
#define MSIME_FCITX_ACTIONS 1
#endif

#ifndef MSIME_SYSTEM_OPTIONS
#define MSIME_SYSTEM_OPTIONS "/etc/msime-client/runtime-options.json"
#endif

extern char **environ;

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

struct FcitxVoiceMailbox {
  std::mutex mutex;
  std::string partial;
  std::string final;
  uint8_t phase = 0;
  bool phase_seen = false;
  uint8_t level = 0;
  bool level_seen = false;
  bool final_ready = false;
};

extern "C" void fcitxVoiceUpdate(const uint8_t *text, size_t length,
                                  bool final, void *context) noexcept {
  if (!context || (!text && length != 0) || length > 4096) return;
  try {
    auto *mailbox = static_cast<FcitxVoiceMailbox *>(context);
    const std::string value(reinterpret_cast<const char *>(text), length);
    std::lock_guard lock(mailbox->mutex);
    if (final) {
      mailbox->final = value;
      mailbox->final_ready = true;
    } else {
      mailbox->partial = value;
    }
  } catch (...) {}
}

extern "C" void fcitxVoiceStatus(uint8_t phase, void *context) noexcept {
  if (!context || phase > 2) return;
  try {
    auto *mailbox = static_cast<FcitxVoiceMailbox *>(context);
    std::lock_guard lock(mailbox->mutex);
    mailbox->phase = phase;
    mailbox->phase_seen = true;
  } catch (...) {}
}

extern "C" void fcitxVoiceLevel(float level, void *context) noexcept {
  if (!context || !std::isfinite(level) || level < 0.0f || level > 1.0f) return;
  try {
    auto *mailbox = static_cast<FcitxVoiceMailbox *>(context);
    std::lock_guard lock(mailbox->mutex);
    mailbox->level = static_cast<uint8_t>(level * 10.0f + 0.5f);
    mailbox->level_seen = true;
  } catch (...) {}
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

Json voiceProviderOptions(const Json &preferences) {
  const auto voice = preferences.value("voice_input", Json::object());
  Json options = Json::object();
  for (const auto *key : {"sound_enabled", "start_sound", "end_sound",
                          "mute_system_audio", "polish_enabled", "polish_text",
                          "doubao_enable_itn", "doubao_enable_punc", "doubao_enable_ddc",
                          "stream_inline_preedit"}) {
    if (voice.contains(key) && voice.at(key).is_boolean()) options[key] = voice.at(key);
  }
  for (const auto *key : {"capture_backend", "capture_device", "commit_mode", "asr_provider",
                          "asr_model", "asr_resource_id", "doubao_auth_mode",
                          "polish_provider", "polish_model", "doubao_boosting_table_id",
                          "polish_prompt_id"}) {
    if (!voice.contains(key) || !voice.at(key).is_string()) continue;
    auto value = voice.at(key).get<std::string>();
    if (std::strcmp(key, "doubao_auth_mode") == 0 && value != "api_key" && value != "legacy") continue;
    if (value.size() > 512) value.resize(512);
    options[key] = std::move(value);
  }
  return options;
}

bool launchDesktopPanel(const char *panel) {
  if (!panel || !*panel) return false;
  const char *command = std::getenv("MSIME_CLIENT_SETTINGS_COMMAND");
  if (!command || !*command) command = "msime-client-settings";
  const bool about = std::strcmp(panel, "about") == 0;
  const std::string route = about ? "settings:about" : panel;
  const std::string panelValue = about ? "settings" : panel;
  std::vector<std::string> environment;
  for (char **entry = ::environ; entry && *entry; ++entry) {
    const std::string value(*entry);
    if (value.rfind("MSIME_CLIENT_PANEL=", 0) == 0 ||
        value.rfind("MSIME_CLIENT_ROUTE=", 0) == 0 ||
        value.rfind("MSIME_CLIENT_SETTINGS_PAGE=", 0) == 0)
      continue;
    environment.push_back(value);
  }
  environment.push_back("MSIME_CLIENT_PANEL=" + panelValue);
  environment.push_back("MSIME_CLIENT_ROUTE=" + route);
  if (about) environment.push_back("MSIME_CLIENT_SETTINGS_PAGE=about");
  std::vector<char *> environmentPointers;
  environmentPointers.reserve(environment.size() + 1);
  for (auto &value : environment) environmentPointers.push_back(value.data());
  environmentPointers.push_back(nullptr);
  char *arguments[] = {const_cast<char *>(command), nullptr};
  pid_t child = 0;
  return posix_spawnp(&child, command, nullptr, nullptr, arguments,
                      environmentPointers.data()) == 0;
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
    preferences_save_job_ = {};
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
    clipboard_mutation_job_ = {};
    cloud_clipboard_socket_.clear();
    cloud_clipboard_items_.clear();
    cloud_clipboard_job_ = {};
    emoji_items_.clear();
    emoji_job_ = {};
    emoji_job_query_.clear();
    emoji_search_mode_ = false;
    emoji_search_.clear();
    emoji_category_.clear();
    emoji_group_.clear();
    emoji_groups_.clear();
    emoji_groups_job_ = {};
    emoji_group_index_ = 0;
    emoji_offset_ = 0;
    emoji_next_offset_ = 0;
    emoji_complete_ = false;
    emoji_previous_offsets_.clear();
    if (voice_job_.valid() && !voice_socket_.empty() && voice_generation_ != 0) {
      const auto socket = voice_socket_;
      const auto generation = voice_generation_;
      msime_client_string_free(msime_client_voice_provider_cancel(
          reinterpret_cast<const uint8_t *>(socket.data()), socket.size(), generation));
    }
    voice_socket_.clear();
    voice_language_ = "zh-cn";
    voice_options_ = Json::object();
    voice_enabled_ = true;
    voice_hotkey_ctrl_f9_ = true;
    voice_hotkey_ralt_ = true;
    voice_ralt_held_ = false;
    voice_f9_held_ = false;
    voice_job_ = {};
    voice_mailbox_.reset();
    voice_generation_ = 0;
    voice_partial_seen_ = false;
    voice_phase_seen_ = false;
    voice_level_seen_ = false;
    voice_loading_ = false;
    chinese_punctuation_ = true;
    paired_punctuation_ = true;
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
  bool toggleNineKey() {
    if (!session_ || view_.value("scheme", 0u) != 0) return false;
    const bool enabled = !view_.value("nine_key", false);
    view_ = response(msime_client_set_nine_key_mode(session_, enabled));
    saveStringPreference("touch_keyboard_layout", enabled ? "nine_key" : "twenty_six_key");
    render();
    return true;
  }
  bool toggleHelpcode() {
    if (!session_ || (view_.value("scheme", 0u) != 0 && view_.value("scheme", 0u) != 1))
      return false;
    const std::string section = view_.value("scheme", 0u) == 1 ? "shuangpin_helpcode" : "quanpin_helpcode";
    const bool enabled = !preferences_.value(section, Json::object()).value("enabled", true);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"][section]["enabled"] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveNestedBooleanPreference(section.c_str(), "enabled", enabled);
    render();
    return true;
  }
  bool toggleQuanpinAutocorrect(const char *key) {
    if (!session_ || view_.value("scheme", 0u) != 0 || !key || !*key) return false;
    const bool enabled = !preferences_.value("quanpin", Json::object()).value(key, false);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"]["quanpin"][key] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveNestedBooleanPreference("quanpin", key, enabled);
    render();
    return true;
  }
  bool toggleMixedEnglish() {
    if (!session_) return false;
    const bool enabled = !preferences_.value("mixed_input", Json::object()).value("english", true);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"]["mixed_input"]["english"] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveNestedBooleanPreference("mixed_input", "english", enabled);
    render();
    return true;
  }
  bool toggleMixedCandidate(const char *key) {
    if (!session_ || !key || !*key) return false;
    const bool enabled = !preferences_.value("mixed_input", Json::object()).value(key, false);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"]["mixed_input"][key] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveNestedBooleanPreference("mixed_input", key, enabled);
    render();
    return true;
  }
  bool toggleEnglishGloss() {
    if (!session_) return false;
    const bool enabled = !preferences_.value("candidate_english_gloss", false);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"]["candidate_english_gloss"] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveBooleanPreference("candidate_english_gloss", enabled);
    translation_query_.clear();
    translation_pending_.clear();
    render();
    return true;
  }
  bool toggleTopLevelBoolean(const char *key, bool fallback = false) {
    if (!session_ || !key || !*key) return false;
    const bool enabled = !preferences_.value(key, fallback);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"][key] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveBooleanPreference(key, enabled);
    render();
    return true;
  }
  bool toggleWordCharacter() {
    if (!session_) return false;
    const bool enabled = !preferences_.value("word_character", Json::object()).value("enabled", true);
    auto snapshot = preferences_snapshot_;
    if (!snapshot.is_object() || !snapshot.contains("revision") ||
        !snapshot.contains("preferences")) return false;
    snapshot["preferences"]["word_character"]["enabled"] = enabled;
    const auto encoded = snapshot.dump();
    view_ = response(msime_client_update_preferences(
        session_, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())).at("view");
    preferences_ = snapshot.at("preferences");
    preferences_snapshot_ = std::move(snapshot);
    saveNestedBooleanPreference("word_character", "enabled", enabled);
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
  void saveBooleanPreference(const char *key, bool enabled) {
    if (!key || !*key || options_path_.empty() || private_) return;
    const auto directory = options_path_;
    const std::string preference(key);
    preferences_save_job_ = std::async(std::launch::async, [directory, preference, enabled] {
      auto snapshot = response(msime_client_load_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size()));
      if (!snapshot.is_object() || !snapshot.contains("revision") ||
          !snapshot.contains("preferences") || !snapshot.at("preferences").is_object())
        return Json::object();
      snapshot["preferences"][preference] = enabled;
      const auto encoded = snapshot.dump();
      return response(msime_client_save_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size(),
          snapshot.at("revision").get<uint64_t>(),
          reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    }).share();
  }
  void saveStringPreference(const char *key, const std::string &value) {
    if (!key || !*key || options_path_.empty() || private_) return;
    const auto directory = options_path_;
    const std::string preference(key);
    preferences_save_job_ = std::async(std::launch::async, [directory, preference, value] {
      auto snapshot = response(msime_client_load_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size()));
      if (!snapshot.is_object() || !snapshot.contains("revision") ||
          !snapshot.contains("preferences") || !snapshot.at("preferences").is_object())
        return Json::object();
      snapshot["preferences"][preference] = value;
      const auto encoded = snapshot.dump();
      return response(msime_client_save_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size(),
          snapshot.at("revision").get<uint64_t>(),
          reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    }).share();
  }
  void saveNestedBooleanPreference(const char *object, const char *key, bool enabled) {
    if (!object || !*object || !key || !*key || options_path_.empty() || private_) return;
    const auto directory = options_path_;
    const std::string section(object), preference(key);
    preferences_save_job_ = std::async(std::launch::async,
        [directory, section, preference, enabled] {
      auto snapshot = response(msime_client_load_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size()));
      if (!snapshot.is_object() || !snapshot.contains("revision") ||
          !snapshot.contains("preferences") || !snapshot.at("preferences").is_object())
        return Json::object();
      snapshot["preferences"][section][preference] = enabled;
      const auto encoded = snapshot.dump();
      return response(msime_client_save_preferences(
          reinterpret_cast<const uint8_t *>(directory.data()), directory.size(),
          snapshot.at("revision").get<uint64_t>(),
          reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    }).share();
  }
  bool toggleChinesePunctuation() {
    if (!session_) return false;
    chinese_punctuation_ = !chinese_punctuation_;
    view_ = response(msime_client_set_chinese_punctuation(session_, chinese_punctuation_));
    saveBooleanPreference("chinese_punctuation", chinese_punctuation_);
    render();
    return true;
  }
  bool togglePairedPunctuation() {
    if (!session_) return false;
    paired_punctuation_ = !paired_punctuation_;
    view_ = response(msime_client_set_paired_punctuation(session_, paired_punctuation_));
    saveBooleanPreference("paired_punctuation", paired_punctuation_);
    render();
    return true;
  }
  bool toggleCandidateTranslations() {
    if (!session_) return false;
    const bool enabled = !preferences_.value("candidate_translations", false);
    preferences_["candidate_translations"] = enabled;
    if (!enabled && view_.contains("generation")) {
      const auto empty = std::string("[]");
      view_ = response(msime_client_apply_translations(
          session_, view_.at("generation"),
          reinterpret_cast<const uint8_t *>(empty.data()), empty.size())).at("view");
      translation_query_.clear();
      translation_pending_.clear();
    }
    saveBooleanPreference("candidate_translations", enabled);
    render();
    return true;
  }
  bool cyclePunctuationLock() {
    if (!session_) return false;
    punctuation_lock_ = static_cast<uint8_t>((punctuation_lock_ + 1) % 3);
    view_ = response(msime_client_set_punctuation_lock(session_, punctuation_lock_));
    saveStringPreference("punctuation_lock", punctuation_lock_ == 1 ? "chinese" :
                                                     punctuation_lock_ == 2 ? "english" : "follow");
    render();
    return true;
  }
  bool cycleTranslationLanguage() {
    if (!session_) return false;
    static constexpr std::array<const char *, 7> languages = {
        "en", "fr", "ja", "es", "ru", "de", "ko"};
    const auto current = preferences_.value("translation_target_language", std::string("en"));
    auto it = std::find(languages.begin(), languages.end(), current);
    const auto next = it == languages.end() || std::next(it) == languages.end()
        ? languages.front() : *std::next(it);
    preferences_["translation_target_language"] = next;
    const auto empty = std::string("[]");
    view_ = response(msime_client_apply_translations(
        session_, view_.at("generation"),
        reinterpret_cast<const uint8_t *>(empty.data()), empty.size())).at("view");
    translation_query_.clear();
    translation_pending_.clear();
    saveStringPreference("translation_target_language", next);
    render();
    return true;
  }
  bool toggleCloudCandidates() {
    if (!session_) return false;
    const bool enabled = !preferences_.value("cloud_candidates", true);
    preferences_["cloud_candidates"] = enabled;
    if (!enabled && !online_query_.empty()) {
      const auto empty = std::string("[]");
      view_ = response(msime_client_apply_online_candidates(
          session_, reinterpret_cast<const uint8_t *>(online_query_.data()), online_query_.size(),
          reinterpret_cast<const uint8_t *>(empty.data()), empty.size(), 0)).at("view");
      ++online_epoch_;
      online_query_.clear();
      online_slots_[0].query.clear();
      online_slots_[1].query.clear();
    }
    saveBooleanPreference("cloud_candidates", enabled);
    render();
    return true;
  }
  bool toggleAiCandidates() {
    if (!session_) return false;
    auto &assistant = preferences_["ai_assistant"];
    const bool enabled = !assistant.value("enabled", false);
    assistant["enabled"] = enabled;
    if (!enabled && !online_query_.empty()) {
      const auto empty = std::string("[]");
      view_ = response(msime_client_apply_online_candidates(
          session_, reinterpret_cast<const uint8_t *>(online_query_.data()), online_query_.size(),
          reinterpret_cast<const uint8_t *>(empty.data()), empty.size(), 1)).at("view");
      ++online_epoch_;
      online_query_.clear();
      online_slots_[0].query.clear();
      online_slots_[1].query.clear();
    }
    saveNestedBooleanPreference("ai_assistant", "enabled", enabled);
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
    chinese_punctuation_ = preferences_.value("chinese_punctuation", true);
    paired_punctuation_ = preferences_.value("paired_punctuation", true);
    const auto punctuationLock = preferences_.value("punctuation_lock", std::string("follow"));
    punctuation_lock_ = punctuationLock == "chinese" ? 1 : punctuationLock == "english" ? 2 : 0;
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
    const auto voicePreferences = preferences_.value("voice_input", Json::object());
    voice_enabled_ = voicePreferences.value("enabled", true);
    voice_hotkey_ctrl_f9_ = voicePreferences.value("hotkey_ctrl_f9", true);
    voice_hotkey_ralt_ = voicePreferences.value("hotkey_ralt", true);
    voice_language_ = voicePreferences.value("language", std::string("zh-cn"));
    voice_options_ = voiceProviderOptions(preferences_);
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
      if (preferences_save_job_.valid()) {
        if (preferences_save_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        preferences_save_job_.get();
        preferences_save_job_ = {};
      }
      if (preferences_job_.valid()) {
        if (preferences_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto snapshot = preferences_job_.get();
        preferences_job_ = {};
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
            chinese_punctuation_ = preferences_.value("chinese_punctuation", chinese_punctuation_);
            paired_punctuation_ = preferences_.value("paired_punctuation", paired_punctuation_);
            const auto punctuationLock = preferences_.value("punctuation_lock", std::string("follow"));
            punctuation_lock_ = punctuationLock == "chinese" ? 1 : punctuationLock == "english" ? 2 : 0;
            navigation_ = preferences_.value("navigation", Json::object());
            const auto wordCharacter = preferences_.value("word_character", Json::object());
            word_character_enabled_ = wordCharacter.value("enabled", true);
            word_character_minus_equal_ = wordCharacter.value("keys", std::string("brackets")) == "minus_equal";
            const auto voicePreferences = preferences_.value("voice_input", Json::object());
            voice_enabled_ = voicePreferences.value("enabled", voice_enabled_);
            voice_hotkey_ctrl_f9_ = voicePreferences.value("hotkey_ctrl_f9", voice_hotkey_ctrl_f9_);
            voice_hotkey_ralt_ = voicePreferences.value("hotkey_ralt", voice_hotkey_ralt_);
            voice_language_ = voicePreferences.value("language", voice_language_);
            voice_options_ = voiceProviderOptions(preferences_);
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
        slot.job = {};
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
                if (result.is_object()) {
                  for (const auto &item : result.value("translations", Json::array()))
                    local.push_back(item);
                  const auto userData = query.value("user_data", std::string{});
                  const auto target = query.value("target_language", std::string{});
                  if (target == "en" && !userData.empty()) {
                    auto translations = result.value("translations", Json::array());
                    if (translations.is_array() && translations.size() > 9)
                      translations.erase(translations.begin() + 9, translations.end());
                    const auto save = Json{{"target_language", target},
                                           {"translations", std::move(translations)}}.dump();
                    msime_client_string_free(msime_client_translation_gloss_save(
                        reinterpret_cast<const uint8_t *>(save.data()), save.size(),
                        reinterpret_cast<const uint8_t *>(userData.data()), userData.size()));
                  }
                }
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
        translation_job_ = {};
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
      if (clipboard_mutation_job_.valid()) {
        if (clipboard_mutation_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        clipboard_mutation_job_.get();
        clipboard_mutation_job_ = {};
        clipboard_items_.clear();
        clipboard_loading_ = false;
      }
      if (clipboard_job_.valid()) {
        if (clipboard_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = clipboard_job_.get();
        clipboard_job_ = {};
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
  bool removeClipboard(size_t index) {
    if (restricted() || privateInput() || !ic_.hasFocus() || clipboard_path_.empty()) return false;
    refreshClipboard();
    if (clipboard_mutation_job_.valid() || index >= clipboard_items_.size()) return false;
    const auto &item = clipboard_items_.at(index);
    const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
    if (text.empty()) return false;
    const auto path = clipboard_path_;
    clipboard_mutation_job_ = std::async(std::launch::async, [path, text] {
      const auto request = Json{{"directory", path}, {"text", text}}.dump();
      auto raw = response(msime_client_remove_clipboard_history(
          reinterpret_cast<const uint8_t *>(request.data()), request.size()));
      return raw.is_object() ? raw : Json::object();
    }).share();
    return true;
  }
  bool clearClipboard() {
    if (restricted() || privateInput() || !ic_.hasFocus() || clipboard_path_.empty()) return false;
    refreshClipboard();
    if (clipboard_mutation_job_.valid() || clipboard_items_.empty()) return false;
    std::vector<std::string> texts;
    for (const auto &item : clipboard_items_) {
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) texts.push_back(text);
    }
    if (texts.empty()) return false;
    const auto path = clipboard_path_;
    clipboard_mutation_job_ = std::async(std::launch::async, [path, texts = std::move(texts)] {
      Json result = Json::object();
      for (const auto &text : texts) {
        const auto request = Json{{"directory", path}, {"text", text}}.dump();
        result = response(msime_client_remove_clipboard_history(
            reinterpret_cast<const uint8_t *>(request.data()), request.size()));
      }
      return result;
    }).share();
    return true;
  }
  void refreshCloudClipboard() {
    try {
      if (cloud_clipboard_job_.valid()) {
        if (cloud_clipboard_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = cloud_clipboard_job_.get();
        cloud_clipboard_job_ = {};
        if (ic_.hasFocus() && !restricted() && !privateInput() && result.is_object())
          cloud_clipboard_items_ = result.value("entries", Json::array());
      }
    } catch (...) { cloud_clipboard_items_.clear(); }
  }
  bool pasteCloudClipboard(size_t index = 0) {
    if (cloud_clipboard_socket_.empty() || restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshCloudClipboard();
    if (index < cloud_clipboard_items_.size()) {
      const auto &item = cloud_clipboard_items_.at(index);
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) { ic_.commitString(text); return true; }
    }
    if (index != 0) return false;
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
  bool requestCloudClipboard() { return pasteCloudClipboard(); }
  void refreshEmoji() {
    try {
      if (emoji_groups_job_.valid() &&
          emoji_groups_job_.wait_for(std::chrono::seconds(0)) == std::future_status::ready) {
        auto result = emoji_groups_job_.get();
        emoji_groups_job_ = {};
        if (result.is_object()) {
          emoji_groups_.clear();
          for (const auto &item : result.value("groups", Json::array()))
            if (item.is_string() && !item.get<std::string>().empty()) emoji_groups_.push_back(item.get<std::string>());
        }
      }
      if (emoji_job_.valid()) {
        if (emoji_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return;
        auto result = emoji_job_.get();
        emoji_job_ = {};
        const auto requestQuery = emoji_job_query_;
        emoji_job_query_.clear();
        if (ic_.hasFocus() && !restricted() && !privateInput() &&
            requestQuery == emoji_search_ && result.is_object()) {
          emoji_items_ = result.value("items", Json::array());
          emoji_next_offset_ = result.value("next_offset", emoji_offset_ + emoji_items_.size());
          emoji_complete_ = result.value("complete", true);
        } else if (emoji_search_mode_ && requestQuery != emoji_search_ && ic_.hasFocus() &&
                   !restricted() && !privateInput()) {
          emoji_items_.clear();
          requestEmojiPage(0);
        }
      }
    } catch (...) { emoji_items_.clear(); }
  }
  bool requestEmojiPage(size_t offset) {
    if (emoji_job_.valid() || resources_.empty()) return false;
    const auto resources = resources_;
    const auto category = emoji_category_;
    const auto group = emoji_group_;
    const auto search = emoji_search_;
    emoji_offset_ = offset;
    emoji_job_query_ = search;
    emoji_job_ = std::async(std::launch::async, [resources, category, group, search, offset] {
      const auto query = Json{{"limit", 5}, {"offset", offset}, {"cursor", true},
                              {"category", category}, {"group", group}, {"search", search}}.dump();
      auto result = response(msime_client_emoji_catalog_request(
          reinterpret_cast<const uint8_t *>(query.data()), query.size(),
          reinterpret_cast<const uint8_t *>(resources.data()), resources.size()));
      return result.is_object() ? result : Json::object();
    }).share();
    return true;
  }
  bool beginEmojiSearch() {
    if (restricted() || privateInput() || !ic_.hasFocus() || resources_.empty()) return false;
    emoji_search_mode_ = true;
    emoji_search_.clear();
    emoji_items_.clear();
    emoji_offset_ = 0;
    emoji_next_offset_ = 0;
    emoji_complete_ = false;
    emoji_previous_offsets_.clear();
    if (!emoji_job_.valid()) requestEmojiPage(0);
    render();
    return true;
  }
  void endEmojiSearch() {
    if (!emoji_search_mode_) return;
    emoji_search_mode_ = false;
    emoji_search_.clear();
    emoji_items_.clear();
    render();
  }
  bool insertEmoji(size_t index = 0) {
    if (restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshEmoji();
    if (index < emoji_items_.size()) {
      const auto &item = emoji_items_.at(index);
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) { ic_.commitString(text); return true; }
    }
    if (index != 0 || !emoji_items_.empty()) return false;
    return requestEmojiPage(0);
  }
  bool nextEmojiPage() {
    if (restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshEmoji();
    if (emoji_complete_ || emoji_job_.valid()) return false;
    emoji_previous_offsets_.push_back(emoji_offset_);
    return requestEmojiPage(emoji_next_offset_);
  }
  bool previousEmojiPage() {
    if (restricted() || privateInput() || !ic_.hasFocus()) return false;
    refreshEmoji();
    if (emoji_job_.valid() || emoji_previous_offsets_.empty()) return false;
    const auto offset = emoji_previous_offsets_.back();
    emoji_previous_offsets_.pop_back();
    return requestEmojiPage(offset);
  }
  bool cycleEmojiCategory() {
    if (restricted() || privateInput() || !ic_.hasFocus() || emoji_job_.valid()) return false;
    static constexpr std::array<const char *, 3> categories = {"", "kaomoji", "symbols"};
    auto it = std::find(categories.begin(), categories.end(), emoji_category_);
    emoji_category_ = it == categories.end() || std::next(it) == categories.end()
        ? categories.front() : *std::next(it);
    emoji_group_.clear();
    emoji_groups_.clear();
    emoji_group_index_ = 0;
    emoji_items_.clear();
    emoji_offset_ = 0;
    emoji_next_offset_ = 0;
    emoji_complete_ = false;
    emoji_previous_offsets_.clear();
    return requestEmojiPage(0);
  }
  bool cycleEmojiGroup() {
    if (restricted() || privateInput() || !ic_.hasFocus() || emoji_job_.valid() ||
        emoji_groups_job_.valid()) return false;
    if (emoji_groups_.empty()) {
      if (resources_.empty()) return false;
      const auto resources = resources_;
      const auto category = emoji_category_;
      emoji_groups_job_ = std::async(std::launch::async, [resources, category] {
        const auto query = Json{{"limit", 1}, {"list_groups", true}, {"category", category}}.dump();
        auto result = response(msime_client_emoji_catalog_request(
            reinterpret_cast<const uint8_t *>(query.data()), query.size(),
            reinterpret_cast<const uint8_t *>(resources.data()), resources.size()));
        return result.is_object() ? result : Json::object();
      }).share();
      return false;
    }
    emoji_group_index_ = (emoji_group_index_ + 1) % (emoji_groups_.size() + 1);
    emoji_group_ = emoji_group_index_ == 0 ? std::string{} : emoji_groups_.at(emoji_group_index_ - 1);
    emoji_items_.clear();
    emoji_offset_ = 0;
    emoji_next_offset_ = 0;
    emoji_complete_ = false;
    emoji_previous_offsets_.clear();
    return requestEmojiPage(0);
  }
  bool refreshVoice() {
    try {
      const auto mailbox = voice_mailbox_;
      if (mailbox && ic_.hasFocus() && !restricted() && !privateInput()) {
        std::string partial;
        uint8_t phase = 0, level = 0;
        bool phaseSeen = false, levelSeen = false;
        {
          std::lock_guard lock(mailbox->mutex);
          partial = mailbox->partial;
          phase = mailbox->phase;
          phaseSeen = mailbox->phase_seen;
          level = mailbox->level;
          levelSeen = mailbox->level_seen;
        }
        if (!partial.empty() || phaseSeen || levelSeen) {
          voice_partial_seen_ = true;
          voice_phase_seen_ = voice_phase_seen_ || phaseSeen;
          voice_level_seen_ = voice_level_seen_ || levelSeen;
          const char *phaseLabel[] = {"录音中", "识别中", "整理中"};
          std::string status = phaseSeen ? phaseLabel[std::min<size_t>(phase, 2)] : "录音中";
          if (levelSeen) status += " " + std::string(level, '#');
          if (!partial.empty()) status += "：" + partial;
          ic_.inputPanel().setAuxUp(fcitx::Text("语音：" + status));
          ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        }
      }
      if (!voice_job_.valid()) return false;
      if (voice_job_.wait_for(std::chrono::seconds(0)) != std::future_status::ready) return false;
      auto result = voice_job_.get();
      voice_job_ = {};
      voice_loading_ = false;
      if (session_ && ic_.hasFocus() && !restricted() && !privateInput() && result.is_object()) {
        auto text = result.value("text", std::string{});
        if (mailbox) {
          std::lock_guard lock(mailbox->mutex);
          if (text.empty() && mailbox->final_ready) text = mailbox->final;
        }
        ic_.inputPanel().setAuxUp(fcitx::Text());
        ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
        voice_mailbox_.reset();
        if (!text.empty()) { ic_.commitString(text); return true; }
      }
    } catch (...) { voice_loading_ = false; voice_mailbox_.reset(); }
    return false;
  }
  bool requestVoice() {
    if (!voice_enabled_ || voice_socket_.empty() || restricted() || privateInput() || !ic_.hasFocus() || voice_loading_) return false;
    if (refreshVoice()) return true;
    if (voice_loading_) return false;
    voice_loading_ = true;
    const auto socket = voice_socket_;
    const auto generation = view_.value("generation", uint64_t{});
    const auto language = voice_language_;
    const auto options = voice_options_;
    voice_generation_ = generation;
    voice_mailbox_ = std::make_shared<FcitxVoiceMailbox>();
    voice_partial_seen_ = false;
    voice_phase_seen_ = false;
    voice_level_seen_ = false;
    const auto mailbox = voice_mailbox_;
    voice_job_ = std::async(std::launch::async, [socket, generation, language, options, mailbox] {
      const auto query = Json{{"language", language}, {"generation", generation},
                              {"options", options}, {"stream", true}}.dump();
      auto result = response(msime_client_voice_provider_stream_feedback(
          reinterpret_cast<const uint8_t *>(query.data()), query.size(),
          reinterpret_cast<const uint8_t *>(socket.data()), socket.size(),
          fcitxVoiceUpdate, fcitxVoiceStatus, fcitxVoiceLevel, mailbox.get()));
      return result.is_object() ? result : Json::object();
    }).share();
    return true;
  }
  bool stopVoice() {
    if (!voice_loading_ || voice_socket_.empty() || voice_generation_ == 0) return false;
    const auto socket = voice_socket_;
    msime_client_string_free(msime_client_voice_provider_stop(
        reinterpret_cast<const uint8_t *>(socket.data()), socket.size(), voice_generation_));
    return true;
  }
  bool cancelVoice() {
    if (!voice_loading_) return false;
    const auto socket = voice_socket_;
    const auto generation = voice_generation_;
    if (!socket.empty() && generation != 0)
      msime_client_string_free(msime_client_voice_provider_cancel(
          reinterpret_cast<const uint8_t *>(socket.data()), socket.size(), generation));
    voice_job_ = {};
    voice_mailbox_.reset();
    voice_loading_ = false;
    voice_partial_seen_ = false;
    voice_phase_seen_ = false;
    voice_level_seen_ = false;
    ic_.inputPanel().setAuxUp(fcitx::Text());
    ic_.updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
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
  bool removeCandidateSlot(size_t slot) {
    if (!ensure() || restricted() || privateInput() || !ic_.hasFocus()) return false;
    const auto candidates = view_.value("candidates", Json::array());
    if (!candidates.is_array() || slot >= candidates.size()) return false;
    const auto &candidate = candidates.at(slot);
    if (!candidate.is_object() ||
        !msime::linux_host::candidate_dictionary_removal_available(
            view_.value("scheme", 0u), candidate.value("source", 0u),
            candidate.value("text", std::string{}))) return false;
    const auto &id = candidate.value("id", Json::object());
    if (!id.is_object() || !id.contains("generation") || !id.contains("index")) return false;
    return apply(msime_client_remove_candidate(session_, id.at("generation"), id.at("index")));
  }
  bool resetCache() {
    if (!ensure() || restricted() || privateInput() || !ic_.hasFocus()) return false;
    return apply(msime_client_reset_cache(session_));
  }
  bool toggleTraditional() {
    if (!session_ || view_.value("scheme", 0u) == 3) return false;
    traditional_ = !traditional_;
    if (!options_path_.empty() && !private_) {
      const auto directory = options_path_;
      const auto enabled = traditional_;
      preferences_save_job_ = std::async(std::launch::async, [directory, enabled] {
        auto snapshot = response(msime_client_load_preferences(
            reinterpret_cast<const uint8_t *>(directory.data()), directory.size()));
        if (!snapshot.is_object() || !snapshot.contains("revision") ||
            !snapshot.contains("preferences")) return Json::object();
        snapshot["preferences"]["traditional_chinese_output"] = enabled;
        const auto encoded = snapshot.dump();
        return response(msime_client_save_preferences(
            reinterpret_cast<const uint8_t *>(directory.data()), directory.size(),
            snapshot.at("revision").get<uint64_t>(),
            reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
      }).share();
    }
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
  std::shared_future<Json> preferences_save_job_;
  std::unique_ptr<fcitx::EventSourceTime> preferences_timer_;
  fcitx::InputContext &ic_;
  FcitxEngine *engine_;
  bool private_ = false;
  bool traditional_ = false;
  bool chinese_punctuation_ = true;
  bool paired_punctuation_ = true;
  uint8_t punctuation_lock_ = 0;
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
  std::shared_future<Json> clipboard_mutation_job_;
  std::string cloud_clipboard_socket_;
  Json cloud_clipboard_items_ = Json::array();
  std::shared_future<Json> cloud_clipboard_job_;
  Json emoji_items_ = Json::array();
  std::shared_future<Json> emoji_job_;
  std::string emoji_job_query_;
  bool emoji_search_mode_ = false;
  std::string emoji_search_;
  std::string emoji_category_;
  std::string emoji_group_;
  std::vector<std::string> emoji_groups_;
  std::shared_future<Json> emoji_groups_job_;
  size_t emoji_group_index_ = 0;
  size_t emoji_offset_ = 0;
  size_t emoji_next_offset_ = 0;
  bool emoji_complete_ = false;
  std::vector<size_t> emoji_previous_offsets_;
  std::string voice_socket_;
  std::string voice_language_ = "zh-cn";
  Json voice_options_ = Json::object();
  bool voice_enabled_ = true;
  bool voice_hotkey_ctrl_f9_ = true;
  bool voice_hotkey_ralt_ = true;
  bool voice_ralt_held_ = false;
  bool voice_f9_held_ = false;
  std::shared_future<Json> voice_job_;
  std::shared_ptr<FcitxVoiceMailbox> voice_mailbox_;
  uint64_t voice_generation_ = 0;
  bool voice_partial_seen_ = false;
  bool voice_phase_seen_ = false;
  bool voice_level_seen_ = false;
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

class FcitxNineKeyAction : public fcitx::Action {
public:
  explicit FcitxNineKeyAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "九键"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->view_.value("scheme", 0u) == 0 &&
           state->view_.value("nine_key", false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->view_.value("scheme", 0u) == 0) {
        state->toggleNineKey();
        update(ic);
      }
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxHelpcodeAction : public fcitx::Action {
public:
  explicit FcitxHelpcodeAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "辅助码"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    if (!state->session_) return false;
    const auto scheme = state->view_.value("scheme", 0u);
    if (scheme != 0 && scheme != 1) return false;
    const auto section = scheme == 1 ? "shuangpin_helpcode" : "quanpin_helpcode";
    return state->preferences_.value(section, Json::object()).value("enabled", true);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleHelpcode()) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxAutocorrectAction : public fcitx::Action {
public:
  enum class Mode { Transposition, Neighbor };
  FcitxAutocorrectAction(fcitx::FactoryFor<FcitxState> *factory, Mode mode)
      : factory_(factory), mode_(mode) { setCheckable(true); }
  std::string shortText(fcitx::InputContext *) const override {
    return mode_ == Mode::Transposition ? "拼音错位纠错" : "拼音邻键纠错";
  }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->view_.value("scheme", 0u) != 0) return false;
    const auto key = mode_ == Mode::Transposition ? "autocorrect_transposition" : "autocorrect_neighbor";
    return state->preferences_.value("quanpin", Json::object()).value(key, false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      const auto key = mode_ == Mode::Transposition ? "autocorrect_transposition" : "autocorrect_neighbor";
      if (state->ensure() && state->toggleQuanpinAutocorrect(key)) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  Mode mode_;
};

class FcitxMixedEnglishAction : public fcitx::Action {
public:
  explicit FcitxMixedEnglishAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "混合英文"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("mixed_input", Json::object())
        .value("english", true);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleMixedEnglish()) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxMixedCandidateAction : public fcitx::Action {
public:
  FcitxMixedCandidateAction(fcitx::FactoryFor<FcitxState> *factory, const char *key,
                            const char *label)
      : factory_(factory), key_(key), label_(label) { setCheckable(true); }
  std::string shortText(fcitx::InputContext *) const override { return label_; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("mixed_input", Json::object())
        .value(key_, false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleMixedCandidate(key_)) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  const char *key_;
  const char *label_;
};

class FcitxEnglishGlossAction : public fcitx::Action {
public:
  explicit FcitxEnglishGlossAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "英文释义"; }
  std::string icon(fcitx::InputContext *) const override { return "accessories-dictionary"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("candidate_english_gloss", false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleEnglishGloss()) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxWordCharacterAction : public fcitx::Action {
public:
  explicit FcitxWordCharacterAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "以词定字"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("word_character", Json::object())
        .value("enabled", true);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleWordCharacter()) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxNumberRowAction : public fcitx::Action {
public:
  explicit FcitxNumberRowAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "数字选词"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("number_row_selection", true);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure() && state->toggleTopLevelBoolean("number_row_selection", true)) update(ic);
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxPunctuationAction : public fcitx::Action {
public:
  enum class Mode { Chinese, Paired };
  FcitxPunctuationAction(fcitx::FactoryFor<FcitxState> *factory, Mode mode)
      : factory_(factory), mode_(mode) { setCheckable(true); }
  std::string shortText(fcitx::InputContext *) const override {
    return mode_ == Mode::Chinese ? "中文标点" : "成对标点";
  }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    if (!state->session_) return false;
    return mode_ == Mode::Chinese ? state->chinese_punctuation_ : state->paired_punctuation_;
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted()) return;
    try {
      if (!state->ensure()) return;
      if (mode_ == Mode::Chinese) state->toggleChinesePunctuation();
      else state->togglePairedPunctuation();
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

class FcitxCandidateTranslationAction : public fcitx::Action {
public:
  explicit FcitxCandidateTranslationAction(fcitx::FactoryFor<FcitxState> *factory)
      : factory_(factory) { setCheckable(true); }
  std::string shortText(fcitx::InputContext *) const override { return "候选翻译"; }
  std::string icon(fcitx::InputContext *) const override { return "input-keyboard"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("candidate_translations", false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure()) {
        state->toggleCandidateTranslations();
        update(ic);
      }
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxPunctuationLockAction : public fcitx::SimpleAction {
public:
  explicit FcitxPunctuationLockAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setLongText("循环切换跟随、固定中文和固定英文标点");
  }
  std::string shortText(fcitx::InputContext *ic) const override {
    if (!ic) return "标点锁定";
    const auto *state = ic->propertyFor(factory_);
    switch (state->punctuation_lock_) {
    case 1: return "标点：中文";
    case 2: return "标点：英文";
    default: return "标点：跟随";
    }
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->session_ && !state->restricted() && !state->privateInput())
        state->cyclePunctuationLock();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxTranslationLanguageAction : public fcitx::SimpleAction {
public:
  explicit FcitxTranslationLanguageAction(fcitx::FactoryFor<FcitxState> *factory)
      : factory_(factory) { setLongText("循环切换候选翻译目标语言"); }
  std::string shortText(fcitx::InputContext *ic) const override {
    if (!ic) return "翻译语言";
    const auto *state = ic->propertyFor(factory_);
    const auto language = state->preferences_.value("translation_target_language", std::string("en"));
    const std::array<std::pair<const char *, const char *>, 7> labels{{
        {"en", "翻译：英语"}, {"fr", "翻译：法语"}, {"ja", "翻译：日语"},
        {"es", "翻译：西班牙语"}, {"ru", "翻译：俄语"}, {"de", "翻译：德语"},
        {"ko", "翻译：韩语"}}};
    for (const auto &[value, label] : labels)
      if (language == value) return label;
    return "翻译语言";
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->session_ && !state->restricted() && !state->privateInput())
        state->cycleTranslationLanguage();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxCloudCandidatesAction : public fcitx::Action {
public:
  explicit FcitxCloudCandidatesAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "云联想"; }
  std::string icon(fcitx::InputContext *) const override { return "network-wireless"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("cloud_candidates", true);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure()) {
        state->toggleCloudCandidates();
        update(ic);
      }
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxAiCandidatesAction : public fcitx::Action {
public:
  explicit FcitxAiCandidatesAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setCheckable(true);
  }
  std::string shortText(fcitx::InputContext *) const override { return "AI 联想"; }
  std::string icon(fcitx::InputContext *) const override { return "applications-science"; }
  bool isChecked(fcitx::InputContext *ic) const override {
    if (!ic) return false;
    const auto *state = ic->propertyFor(factory_);
    return state->session_ && state->preferences_.value("ai_assistant", Json::object())
        .value("enabled", false);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    auto *state = ic->propertyFor(factory_);
    if (!state->session_ || state->restricted() || state->privateInput()) return;
    try {
      if (state->ensure()) {
        state->toggleAiCandidates();
        update(ic);
      }
    } catch (...) {
      state->close();
      state->clearPanel();
    }
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
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

class FcitxDesktopPanelAction : public fcitx::SimpleAction {
public:
  FcitxDesktopPanelAction(fcitx::FactoryFor<FcitxState> *factory,
                          const char *panel, const char *text)
      : panel_(panel), factory_(factory) {
    setShortText(text);
    setLongText(text);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (!state || state->restricted() || state->privateInput() || !state->ensure()) return;
      launchDesktopPanel(panel_);
    } catch (...) {}
  }
private:
  const char *panel_;
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxDesktopToolsAction : public fcitx::SimpleAction {
public:
  FcitxDesktopToolsAction() {
    setShortText("桌面工具");
    setLongText("打开手写、Emoji、剪贴板和设置等桌面工具");
  }
  void setMenu(fcitx::Menu *menu) { fcitx::SimpleAction::setMenu(menu); }
  void activate(fcitx::InputContext *) override {}
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

class FcitxClipboardRemoveAction : public fcitx::SimpleAction {
public:
  FcitxClipboardRemoveAction(fcitx::FactoryFor<FcitxState> *factory, size_t index)
      : factory_(factory), index_(index) {}
  std::string shortText(fcitx::InputContext *ic) const override {
    if (ic && index_ < ic->propertyFor(factory_)->clipboard_items_.size())
      return "删除 " + std::to_string(index_ + 1);
    return "删除剪贴板 " + std::to_string(index_ + 1);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->removeClipboard(index_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  size_t index_;
};

class FcitxClipboardClearAction : public fcitx::SimpleAction {
public:
  explicit FcitxClipboardClearAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("清空历史");
    setLongText("删除全部本地剪贴板历史");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->clearClipboard(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
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

class FcitxCloudClipboardItemAction : public fcitx::SimpleAction {
public:
  FcitxCloudClipboardItemAction(fcitx::FactoryFor<FcitxState> *factory, size_t index)
      : factory_(factory), index_(index) {}
  std::string shortText(fcitx::InputContext *ic) const override {
    if (ic && index_ < ic->propertyFor(factory_)->cloud_clipboard_items_.size()) {
      const auto &item = ic->propertyFor(factory_)->cloud_clipboard_items_.at(index_);
      const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
      if (!text.empty()) {
        const auto clipped = text.substr(0, 40);
        return clipped + (text.size() > clipped.size() ? "…" : "");
      }
    }
    return "云剪贴板 " + std::to_string(index_ + 1);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->pasteCloudClipboard(index_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  size_t index_;
};

class FcitxEmojiAction : public fcitx::SimpleAction {
public:
  explicit FcitxEmojiAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("表情");
    setLongText("浏览并插入本地表情目录");
  }
  void setMenu(fcitx::Menu *menu) { fcitx::SimpleAction::setMenu(menu); }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->insertEmoji(); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxEmojiSearchAction : public fcitx::SimpleAction {
public:
  explicit FcitxEmojiSearchAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("搜索 Emoji");
    setLongText("在本地 Emoji、颜文字和符号目录中搜索");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->ensure()) state->beginEmojiSearch();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxEmojiCategoryAction : public fcitx::SimpleAction {
public:
  explicit FcitxEmojiCategoryAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setLongText("循环切换 Emoji、颜文字和符号目录");
  }
  std::string shortText(fcitx::InputContext *ic) const override {
    if (!ic) return "表情类别";
    const auto category = ic->propertyFor(factory_)->emoji_category_;
    if (category == "kaomoji") return "表情：颜文字";
    if (category == "symbols") return "表情：符号";
    return "表情：Emoji";
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->ensure()) state->cycleEmojiCategory();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxEmojiGroupAction : public fcitx::SimpleAction {
public:
  explicit FcitxEmojiGroupAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setLongText("循环切换当前 Emoji 目录的分组");
  }
  std::string shortText(fcitx::InputContext *ic) const override {
    if (!ic) return "表情分组";
    const auto *state = ic->propertyFor(factory_);
    return state->emoji_group_.empty() ? "表情：全部" : "表情：" + state->emoji_group_;
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->ensure()) state->cycleEmojiGroup();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxEmojiItemAction : public fcitx::SimpleAction {
public:
  FcitxEmojiItemAction(fcitx::FactoryFor<FcitxState> *factory, size_t index)
      : factory_(factory), index_(index) {}
  std::string shortText(fcitx::InputContext *ic) const override {
    if (ic) {
      const auto *state = ic->propertyFor(factory_);
      if (index_ < state->emoji_items_.size()) {
        const auto &item = state->emoji_items_.at(index_);
        const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
        const auto annotation = item.is_object() ? item.value("annotation", std::string{}) : std::string{};
        if (!text.empty()) return text + (annotation.empty() ? "" : "  " + annotation);
      }
    }
    return "表情 " + std::to_string(index_ + 1);
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try { ic->propertyFor(factory_)->insertEmoji(index_); } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  size_t index_;
};

class FcitxEmojiPageAction : public fcitx::SimpleAction {
public:
  FcitxEmojiPageAction(fcitx::FactoryFor<FcitxState> *factory, bool next)
      : factory_(factory), next_(next) {}
  std::string shortText(fcitx::InputContext *) const override {
    return next_ ? "下一页" : "上一页";
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      if (next_) ic->propertyFor(factory_)->nextEmojiPage();
      else ic->propertyFor(factory_)->previousEmojiPage();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
  bool next_;
};

class FcitxVoiceAction : public fcitx::SimpleAction {
public:
  explicit FcitxVoiceAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("语音");
    setLongText("开始或停止流式语音识别");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->voice_loading_) state->stopVoice();
      else state->requestVoice();
    } catch (...) {}
  }
private:
  fcitx::FactoryFor<FcitxState> *factory_;
};

class FcitxVoiceCancelAction : public fcitx::SimpleAction {
public:
  explicit FcitxVoiceCancelAction(fcitx::FactoryFor<FcitxState> *factory) : factory_(factory) {
    setShortText("取消语音");
    setLongText("取消当前录音、识别或润色，不提交语音结果");
  }
  void activate(fcitx::InputContext *ic) override {
    if (!ic || !ic->hasFocus()) return;
    try {
      auto *state = ic->propertyFor(factory_);
      if (state->voice_loading_) state->cancelVoice();
    } catch (...) {}
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
      if (state->restricted() || state->privateInput()) return;
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
    nine_key_action_.registerAction("msime-nine-key", &instance->userInterfaceManager());
    helpcode_action_.registerAction("msime-helpcode", &instance->userInterfaceManager());
    autocorrect_transposition_action_.registerAction("msime-autocorrect-transposition", &instance->userInterfaceManager());
    autocorrect_neighbor_action_.registerAction("msime-autocorrect-neighbor", &instance->userInterfaceManager());
    mixed_english_action_.registerAction("msime-mixed-english", &instance->userInterfaceManager());
    mixed_emoji_action_.registerAction("msime-mixed-emoji", &instance->userInterfaceManager());
    mixed_kaomoji_action_.registerAction("msime-mixed-kaomoji", &instance->userInterfaceManager());
    english_gloss_action_.registerAction("msime-english-gloss", &instance->userInterfaceManager());
    word_character_action_.registerAction("msime-word-character", &instance->userInterfaceManager());
    number_row_action_.registerAction("msime-number-row", &instance->userInterfaceManager());
    maintenance_action_.registerAction("msime-candidate-tools", &instance->userInterfaceManager());
    clipboard_action_.registerAction("msime-clipboard", &instance->userInterfaceManager());
    cloud_clipboard_action_.registerAction("msime-cloud-clipboard", &instance->userInterfaceManager());
    emoji_action_.registerAction("msime-emoji", &instance->userInterfaceManager());
    emoji_search_action_.registerAction("msime-emoji-search", &instance->userInterfaceManager());
    emoji_category_action_.registerAction("msime-emoji-category", &instance->userInterfaceManager());
    emoji_group_action_.registerAction("msime-emoji-group", &instance->userInterfaceManager());
    voice_action_.registerAction("msime-voice", &instance->userInterfaceManager());
    voice_cancel_action_.registerAction("msime-voice-cancel", &instance->userInterfaceManager());
    desktop_tools_action_.registerAction("msime-desktop-tools", &instance->userInterfaceManager());
    traditional_action_.registerAction("msime-traditional", &instance->userInterfaceManager());
    chinese_punctuation_action_.registerAction("msime-chinese-punctuation", &instance->userInterfaceManager());
    paired_punctuation_action_.registerAction("msime-paired-punctuation", &instance->userInterfaceManager());
    candidate_translation_action_.registerAction("msime-candidate-translations", &instance->userInterfaceManager());
    punctuation_lock_action_.registerAction("msime-punctuation-lock", &instance->userInterfaceManager());
    translation_language_action_.registerAction("msime-translation-language", &instance->userInterfaceManager());
    cloud_candidates_action_.registerAction("msime-cloud-candidates", &instance->userInterfaceManager());
    ai_candidates_action_.registerAction("msime-ai-candidates", &instance->userInterfaceManager());
    clipboard_action_.setMenu(&clipboard_menu_);
    clipboard_menu_.addAction(&clipboard_item1_);
    clipboard_menu_.addAction(&clipboard_item2_);
    clipboard_menu_.addAction(&clipboard_item3_);
    clipboard_menu_.addAction(&clipboard_item4_);
    clipboard_menu_.addAction(&clipboard_item5_);
    clipboard_menu_.addAction(&clipboard_remove1_);
    clipboard_menu_.addAction(&clipboard_remove2_);
    clipboard_menu_.addAction(&clipboard_remove3_);
    clipboard_menu_.addAction(&clipboard_remove4_);
    clipboard_menu_.addAction(&clipboard_remove5_);
    clipboard_menu_.addAction(&clipboard_clear_action_);
    cloud_clipboard_action_.setMenu(&cloud_clipboard_menu_);
    cloud_clipboard_menu_.addAction(&cloud_clipboard_item1_);
    cloud_clipboard_menu_.addAction(&cloud_clipboard_item2_);
    cloud_clipboard_menu_.addAction(&cloud_clipboard_item3_);
    cloud_clipboard_menu_.addAction(&cloud_clipboard_item4_);
    cloud_clipboard_menu_.addAction(&cloud_clipboard_item5_);
    desktop_tools_action_.setMenu(&desktop_tools_menu_);
    desktop_tools_menu_.addAction(&handwriting_action_);
    desktop_tools_menu_.addAction(&keyboard_action_);
    desktop_tools_menu_.addAction(&desktop_emoji_action_);
    desktop_tools_menu_.addAction(&desktop_clipboard_action_);
    desktop_tools_menu_.addAction(&desktop_voice_action_);
    desktop_tools_menu_.addAction(&cloud_dictionary_action_);
    desktop_tools_menu_.addAction(&desktop_cloud_clipboard_action_);
    desktop_tools_menu_.addAction(&settings_action_);
    desktop_tools_menu_.addAction(&about_action_);
    emoji_action_.setMenu(&emoji_menu_);
    emoji_menu_.addAction(&emoji_item1_);
    emoji_menu_.addAction(&emoji_item2_);
    emoji_menu_.addAction(&emoji_item3_);
    emoji_menu_.addAction(&emoji_item4_);
    emoji_menu_.addAction(&emoji_item5_);
    emoji_menu_.addAction(&emoji_previous_action_);
    emoji_menu_.addAction(&emoji_next_action_);
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
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &nine_key_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &helpcode_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &autocorrect_transposition_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &autocorrect_neighbor_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &mixed_english_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &mixed_emoji_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &mixed_kaomoji_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &english_gloss_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &word_character_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &number_row_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &maintenance_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &clipboard_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &cloud_clipboard_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &emoji_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &emoji_search_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &emoji_category_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &emoji_group_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &voice_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &voice_cancel_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &desktop_tools_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &traditional_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &chinese_punctuation_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &paired_punctuation_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &candidate_translation_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &punctuation_lock_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &translation_language_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &cloud_candidates_action_);
    event.inputContext()->statusArea().addAction(fcitx::StatusGroup::InputMethod, &ai_candidates_action_);
    try { if (state->ensure()) state->render(); } catch (...) { unavailable(*state); }
  }
  void deactivate(const fcitx::InputMethodEntry &, fcitx::InputContextEvent &event) override {
    auto *state = event.inputContext()->propertyFor(&factory_);
    event.inputContext()->statusArea().removeAction(&english_action_);
    event.inputContext()->statusArea().removeAction(&width_action_);
    event.inputContext()->statusArea().removeAction(&nine_key_action_);
    event.inputContext()->statusArea().removeAction(&helpcode_action_);
    event.inputContext()->statusArea().removeAction(&autocorrect_transposition_action_);
    event.inputContext()->statusArea().removeAction(&autocorrect_neighbor_action_);
    event.inputContext()->statusArea().removeAction(&mixed_english_action_);
    event.inputContext()->statusArea().removeAction(&mixed_emoji_action_);
    event.inputContext()->statusArea().removeAction(&mixed_kaomoji_action_);
    event.inputContext()->statusArea().removeAction(&english_gloss_action_);
    event.inputContext()->statusArea().removeAction(&word_character_action_);
    event.inputContext()->statusArea().removeAction(&number_row_action_);
    event.inputContext()->statusArea().removeAction(&maintenance_action_);
    event.inputContext()->statusArea().removeAction(&clipboard_action_);
    event.inputContext()->statusArea().removeAction(&cloud_clipboard_action_);
    event.inputContext()->statusArea().removeAction(&emoji_action_);
    event.inputContext()->statusArea().removeAction(&emoji_search_action_);
    event.inputContext()->statusArea().removeAction(&emoji_category_action_);
    event.inputContext()->statusArea().removeAction(&emoji_group_action_);
    event.inputContext()->statusArea().removeAction(&voice_action_);
    event.inputContext()->statusArea().removeAction(&voice_cancel_action_);
    event.inputContext()->statusArea().removeAction(&desktop_tools_action_);
    event.inputContext()->statusArea().removeAction(&traditional_action_);
    event.inputContext()->statusArea().removeAction(&chinese_punctuation_action_);
    event.inputContext()->statusArea().removeAction(&paired_punctuation_action_);
    event.inputContext()->statusArea().removeAction(&candidate_translation_action_);
    event.inputContext()->statusArea().removeAction(&punctuation_lock_action_);
    event.inputContext()->statusArea().removeAction(&translation_language_action_);
    event.inputContext()->statusArea().removeAction(&cloud_candidates_action_);
    event.inputContext()->statusArea().removeAction(&ai_candidates_action_);
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
  FcitxNineKeyAction nine_key_action_{&factory_};
  FcitxHelpcodeAction helpcode_action_{&factory_};
  FcitxAutocorrectAction autocorrect_transposition_action_{&factory_, FcitxAutocorrectAction::Mode::Transposition};
  FcitxAutocorrectAction autocorrect_neighbor_action_{&factory_, FcitxAutocorrectAction::Mode::Neighbor};
  FcitxMixedEnglishAction mixed_english_action_{&factory_};
  FcitxMixedCandidateAction mixed_emoji_action_{&factory_, "emoji", "混合 Emoji"};
  FcitxMixedCandidateAction mixed_kaomoji_action_{&factory_, "kaomoji", "混合颜文字"};
  FcitxEnglishGlossAction english_gloss_action_{&factory_};
  FcitxWordCharacterAction word_character_action_{&factory_};
  FcitxNumberRowAction number_row_action_{&factory_};
  fcitx::Menu maintenance_menu_;
  FcitxMaintenanceAction maintenance_action_{&factory_, 0, "候选维护"};
  FcitxClipboardAction clipboard_action_{&factory_};
  FcitxCloudClipboardAction cloud_clipboard_action_{&factory_};
  FcitxEmojiAction emoji_action_{&factory_};
  FcitxEmojiSearchAction emoji_search_action_{&factory_};
  FcitxEmojiCategoryAction emoji_category_action_{&factory_};
  FcitxEmojiGroupAction emoji_group_action_{&factory_};
  FcitxVoiceAction voice_action_{&factory_};
  FcitxVoiceCancelAction voice_cancel_action_{&factory_};
  FcitxDesktopToolsAction desktop_tools_action_;
  FcitxTraditionalAction traditional_action_{&factory_};
  FcitxPunctuationAction chinese_punctuation_action_{&factory_, FcitxPunctuationAction::Mode::Chinese};
  FcitxPunctuationAction paired_punctuation_action_{&factory_, FcitxPunctuationAction::Mode::Paired};
  FcitxCandidateTranslationAction candidate_translation_action_{&factory_};
  FcitxPunctuationLockAction punctuation_lock_action_{&factory_};
  FcitxTranslationLanguageAction translation_language_action_{&factory_};
  FcitxCloudCandidatesAction cloud_candidates_action_{&factory_};
  FcitxAiCandidatesAction ai_candidates_action_{&factory_};
  fcitx::Menu clipboard_menu_;
  FcitxClipboardItemAction clipboard_item1_{&factory_, 0};
  FcitxClipboardItemAction clipboard_item2_{&factory_, 1};
  FcitxClipboardItemAction clipboard_item3_{&factory_, 2};
  FcitxClipboardItemAction clipboard_item4_{&factory_, 3};
  FcitxClipboardItemAction clipboard_item5_{&factory_, 4};
  FcitxClipboardRemoveAction clipboard_remove1_{&factory_, 0};
  FcitxClipboardRemoveAction clipboard_remove2_{&factory_, 1};
  FcitxClipboardRemoveAction clipboard_remove3_{&factory_, 2};
  FcitxClipboardRemoveAction clipboard_remove4_{&factory_, 3};
  FcitxClipboardRemoveAction clipboard_remove5_{&factory_, 4};
  FcitxClipboardClearAction clipboard_clear_action_{&factory_};
  fcitx::Menu cloud_clipboard_menu_;
  FcitxCloudClipboardItemAction cloud_clipboard_item1_{&factory_, 0};
  FcitxCloudClipboardItemAction cloud_clipboard_item2_{&factory_, 1};
  FcitxCloudClipboardItemAction cloud_clipboard_item3_{&factory_, 2};
  FcitxCloudClipboardItemAction cloud_clipboard_item4_{&factory_, 3};
  FcitxCloudClipboardItemAction cloud_clipboard_item5_{&factory_, 4};
  FcitxMaintenanceAction pin_action_{&factory_, 1, "固定候选"};
  FcitxMaintenanceAction remove_action_{&factory_, 2, "删除候选"};
  FcitxMaintenanceAction fix1_action_{&factory_, 11, "固定到 1"};
  FcitxMaintenanceAction fix2_action_{&factory_, 12, "固定到 2"};
  FcitxMaintenanceAction fix3_action_{&factory_, 13, "固定到 3"};
  FcitxMaintenanceAction fix4_action_{&factory_, 14, "固定到 4"};
  FcitxMaintenanceAction fix5_action_{&factory_, 15, "固定到 5"};
  FcitxMaintenanceAction clear_action_{&factory_, 20, "取消固定"};
  fcitx::Menu desktop_tools_menu_;
  FcitxDesktopPanelAction handwriting_action_{&factory_, "handwriting", "手写识别板"};
  FcitxDesktopPanelAction keyboard_action_{&factory_, "keyboard", "屏幕键盘"};
  FcitxDesktopPanelAction desktop_emoji_action_{&factory_, "emoji", "表情与符号"};
  FcitxDesktopPanelAction desktop_clipboard_action_{&factory_, "clipboard", "本地剪贴板"};
  FcitxDesktopPanelAction desktop_voice_action_{&factory_, "voice", "语音面板"};
  FcitxDesktopPanelAction cloud_dictionary_action_{&factory_, "cloud-dictionary", "云词典"};
  FcitxDesktopPanelAction desktop_cloud_clipboard_action_{&factory_, "cloud-clipboard", "云剪贴板"};
  FcitxDesktopPanelAction settings_action_{&factory_, "settings", "设置"};
  FcitxDesktopPanelAction about_action_{&factory_, "about", "关于"};
  fcitx::Menu emoji_menu_;
  FcitxEmojiItemAction emoji_item1_{&factory_, 0};
  FcitxEmojiItemAction emoji_item2_{&factory_, 1};
  FcitxEmojiItemAction emoji_item3_{&factory_, 2};
  FcitxEmojiItemAction emoji_item4_{&factory_, 3};
  FcitxEmojiItemAction emoji_item5_{&factory_, 4};
  FcitxEmojiPageAction emoji_previous_action_{&factory_, false};
  FcitxEmojiPageAction emoji_next_action_{&factory_, true};
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
  if (emoji_search_mode_)
    ic_.inputPanel().setAuxUp(fcitx::Text("Emoji 搜索：" + emoji_search_));
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
  const auto sym = key.sym();
  const auto states = key.states();
  // An accepted stroke owns its repeats and release, even if modifiers or
  // preferences change while held. Unmatched releases must not stop voice.
  if (sym == FcitxKey_F9 && voice_f9_held_) {
    if (event.isRelease()) voice_f9_held_ = false;
    return true;
  }
  if (sym == FcitxKey_Alt_R && voice_ralt_held_) {
    if (event.isRelease()) {
      voice_ralt_held_ = false;
      if (voice_loading_) stopVoice();
    }
    return true;
  }
  if (event.isRelease()) return false;
  if (sym == FcitxKey_Alt_R && voice_hotkey_ralt_ && voice_enabled_ && !voice_socket_.empty() &&
      !states.testAny(fcitx::KeyStates{fcitx::KeyState::Ctrl, fcitx::KeyState::Shift,
                                       fcitx::KeyState::Super, fcitx::KeyState::Hyper}) &&
      !restricted() && !privateInput() && ic_.hasFocus()) {
    if (!voice_loading_ && !requestVoice()) return false;
    voice_ralt_held_ = true;
    return true;
  }
  if (event.isRelease() || key.isModifier()) return false;
  const bool composing = !view_.value("editing_text", std::string()).empty();
  const bool ctrl = states.test(fcitx::KeyState::Ctrl);
  const bool alt = states.test(fcitx::KeyState::Alt);
  const bool shift = states.test(fcitx::KeyState::Shift);
  if (sym == FcitxKey_F9 && ctrl && !alt && !shift &&
      !states.testAny(fcitx::KeyStates{fcitx::KeyState::Super, fcitx::KeyState::Hyper}) &&
      voice_hotkey_ctrl_f9_ && voice_enabled_ && !voice_socket_.empty() && !restricted() && !privateInput() &&
      ic_.hasFocus()) {
    if (voice_loading_) {
      if (!stopVoice()) return false;
    } else if (!requestVoice()) return false;
    voice_f9_held_ = true;
    return true;
  }
  if (emoji_search_mode_) {
    if (sym == FcitxKey_Escape) {
      endEmojiSearch();
      return true;
    }
    if (states.testAny(fcitx::KeyStates{fcitx::KeyState::Ctrl, fcitx::KeyState::Alt,
                                        fcitx::KeyState::Super, fcitx::KeyState::Hyper}))
      return true;
    if (sym == FcitxKey_BackSpace) {
      if (!emoji_search_.empty()) emoji_search_.pop_back();
      emoji_items_.clear();
      emoji_offset_ = 0;
      emoji_next_offset_ = 0;
      emoji_complete_ = false;
      emoji_previous_offsets_.clear();
      if (!emoji_job_.valid()) requestEmojiPage(0);
      render();
      return true;
    }
    if (sym == FcitxKey_Return || sym == FcitxKey_KP_Enter) {
      refreshEmoji();
      if (!emoji_items_.empty()) {
        const auto &item = emoji_items_.front();
        const auto text = item.is_string() ? item.get<std::string>() : item.value("text", std::string{});
        if (!text.empty()) ic_.commitString(text);
      }
      endEmojiSearch();
      return true;
    }
    const auto searchText = fcitx::Key::keySymToUTF8(sym);
    if (!shift && searchText.size() == 1 &&
        ((searchText[0] >= 'a' && searchText[0] <= 'z') ||
         (searchText[0] >= '0' && searchText[0] <= '9') || searchText == " ")) {
      if (emoji_search_.size() < 256) emoji_search_.append(searchText);
      emoji_items_.clear();
      emoji_offset_ = 0;
      emoji_next_offset_ = 0;
      emoji_complete_ = false;
      emoji_previous_offsets_.clear();
      if (!emoji_job_.valid()) requestEmojiPage(0);
      render();
      return true;
    }
    return true;
  }
  if (ctrl && shift && alt &&
      !states.testAny(fcitx::KeyStates{fcitx::KeyState::Super, fcitx::KeyState::Hyper})) {
    if (sym == FcitxKey_c || sym == FcitxKey_C) return resetCache();
    std::optional<size_t> slot;
    if (sym >= FcitxKey_1 && sym <= FcitxKey_8)
      slot = static_cast<size_t>(sym - FcitxKey_1);
    else if (sym >= FcitxKey_KP_1 && sym <= FcitxKey_KP_8)
      slot = static_cast<size_t>(sym - FcitxKey_KP_1);
    if (slot) return removeCandidateSlot(*slot);
  }
  if (sym == FcitxKey_Escape && voice_loading_) {
    cancelVoice();
    return composing ? command(MSIME_CANCEL) : true;
  }
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

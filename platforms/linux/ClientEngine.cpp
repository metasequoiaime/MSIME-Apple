#include "ClientEngine.h"
#include "ChineseTextConversion.h"
#include "NavigationBindings.h"
#include "WordCharacterBinding.h"
#include "VoiceAction.h"
#include "VoiceWorker.h"
#include "msime_client.h"
#include <algorithm>
#include <cctype>
#include <filesystem>
#include <fstream>
#include <fcntl.h>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <tuple>
#include <cstdlib>
#include <stdexcept>
#include <string_view>
#include <sys/file.h>
#include <unistd.h>
#include <vector>

using Json = nlohmann::json;
struct MsimePreviewEngine;
namespace {
Json configured;
std::optional<bool> global_input_enabled;
void register_properties(IBusEngine *engine);
Json response(char *raw) {
  std::unique_ptr<char, decltype(&msime_client_string_free)> owned(
      raw, msime_client_string_free);
  if (!raw)
    throw std::runtime_error("Missing host response");
  auto document = Json::parse(raw);
  if (!document.at("ok").get<bool>())
    throw std::runtime_error("Host operation failed");
  return document.at("value");
}
std::optional<guint> candidate_text_color(const Json &preferences);
std::optional<guint> candidate_background_color(const Json &preferences);
IBusOrientation candidate_orientation(const Json &preferences);
std::string preedit_style(const Json &preferences);
bool launch_desktop_panel(const char *panel);
struct State;
bool script_conversion_applies(const Json &context);
std::string traditional_display(const State &s, const Json &context,
                                std::string text);
struct State {
  MsimeVoiceWorker voice_worker;
  uint64_t session = 0;
  Json view;
  bool focused = false;
  bool blocked = false;
  bool private_input = false;
  guint preferences_timer = 0;
  bool preferences_loading = false;
  bool input_enabled = true;
  bool mode_scope_global = false;
  bool chinese_punctuation = true;
  bool properties_registered = false;
  std::optional<bool> english_override;
  std::optional<bool> dedicated_english_override;
  std::optional<bool> cloud_candidates_override;
  std::optional<bool> traditional_output_override;
  std::optional<bool> emoji_override;
  std::optional<bool> kaomoji_override;
  std::optional<bool> punctuation_override, autocorrect_override, helpcode_override;
  bool show_helpcode_in_candidate_window = true;
  std::optional<bool> word_character_override;
  std::optional<bool> smart_punctuation_override, smart_repeat_override, paired_punctuation_override;
  std::optional<std::string> punctuation_lock_override;
  std::optional<uint8_t> candidate_page_size_override;
  std::optional<std::string> frequency_mode_override, helpcode_schema_override;
  std::optional<std::string> layout_override, preedit_override, theme_override;
  std::optional<std::string> skin_override, scheme_override, shuangpin_profile_override;
  std::optional<bool> nine_key_override;
  Json local_mode_overrides = Json::object();
  bool fullwidth = false;
  bool english_mode = false;
  bool traditional_output = false;
  std::string candidate_preedit_style = "pinyin";
  bool smart_punctuation = true;
  bool smart_punctuation_repeat = true;
  bool paired_punctuation = true;
  bool pure_shift_candidate = false;
  bool pure_ctrl_candidate = false;
  bool mode_shift_enabled = true;
  bool mode_ctrl_enabled = false;
  bool mode_ctrl_alt_space_enabled = true;
  bool character_set_shortcut_enabled = true;
  bool mode_chord_held = false;
  bool number_row_selection = true;
  std::optional<bool> number_row_override;
  char last_smart_punctuation = 0;
  gint64 last_smart_punctuation_time = 0;
  // A deleted ASCII smart mark keeps this caret position on the Chinese path
  // when the same key is immediately retyped, matching the Windows behavior.
  char smart_punctuation_rejected = 0;
  std::string punctuation_lock = "follow";
  std::string preedit_style = "raw";
  std::optional<guint> candidate_text_color, candidate_background_color;
  IBusOrientation candidate_orientation = IBUS_ORIENTATION_VERTICAL;
  msime::linux_host::NavigationBindings navigation;
  msime::linux_host::WordCharacterBinding word_character;
  std::string clipboard_history_path, online_provider_socket,
      translation_provider_socket;
  std::string voice_provider_socket, voice_language = "zh-cn";
  bool voice_enabled = true;
  bool voice_hotkey_ralt = true;
  bool voice_hotkey_ctrl_win = false;
  bool voice_hotkey_rctrl_ralt = false;
  bool voice_hotkey_hold_space_lock = true;
  bool voice_hotkey_ctrl_f9 = true;
  guint voice_hotkey_consumed_key = 0;
  bool voice_space_consumed = false;
  bool voice_space_locked = false;
  bool voice_active = false;
  uint64_t voice_generation = 0;
  std::string voice_preedit;
  std::shared_ptr<std::atomic_bool> alive =
      std::make_shared<std::atomic_bool>(true);
  std::vector<std::string> clipboard_items_cache;
  uint64_t clipboard_generation = 0;
  bool clipboard_loading = false, clipboard_loaded = false;
  bool online_loading = false, translation_loading = false;
  bool cloud_candidates = true;
  uint64_t provider_epoch = 0;
  void invalidate_providers() {
    ++provider_epoch;
    online_loading = false;
    translation_loading = false;
  }
  std::string surrounding_text;
  guint surrounding_cursor = 0;
  guint surrounding_anchor = 0;
  ~State() {
    alive->store(false);
    close();
  }
  void close() {
    if (voice_active && !voice_provider_socket.empty())
      msime_client_string_free(msime_client_voice_provider_cancel(
          reinterpret_cast<const uint8_t *>(voice_provider_socket.data()),
          voice_provider_socket.size(), voice_generation));
    if (voice_active && session)
      msime_client_string_free(msime_client_voice_cancel(session));
    voice_active = false;
    voice_generation = 0;
    voice_preedit.clear();
    voice_hotkey_consumed_key = 0;
    voice_space_consumed = false;
    voice_space_locked = false;
    pure_shift_candidate = false;
    pure_ctrl_candidate = false;
    mode_chord_held = false;
    voice_worker.cancel_async();
    invalidate_providers();
    ++clipboard_generation;
    clipboard_loading = false;
    clipboard_loaded = false;
    clipboard_items_cache.clear();
    if (session)
      msime_client_string_free(msime_client_destroy(session));
    session = 0;
    view = nullptr;
    surrounding_text.clear();
    surrounding_cursor = 0;
    surrounding_anchor = 0;
    last_smart_punctuation = 0;
    last_smart_punctuation_time = 0;
    smart_punctuation_rejected = 0;
  }
  void open() {
    auto options = configured;
    auto &base_preferences = options["preferences"];
    mode_scope_global =
        base_preferences.value("ime_mode_scope", "app") == "global";
    if (mode_scope_global) {
      if (!global_input_enabled)
        global_input_enabled =
            base_preferences.value("default_ime_mode", "chinese") != "english";
      if (!session)
        input_enabled = *global_input_enabled;
    }
    if (session || blocked || !focused || !input_enabled)
      return;
    number_row_selection = number_row_override.value_or(
        options.value("preferences", Json::object()).value("number_row_selection", true));
    auto &preferences = options["preferences"];
    if (paired_punctuation_override) preferences["paired_punctuation"] = *paired_punctuation_override;
    if (punctuation_lock_override) preferences["punctuation_lock"] = *punctuation_lock_override;
    if (scheme_override) preferences["scheme"] = *scheme_override;
    if (shuangpin_profile_override) preferences["shuangpin_profile"] = *shuangpin_profile_override;
    if (candidate_page_size_override) preferences["candidate_page_size"] = *candidate_page_size_override;
    if (layout_override) preferences["candidate_layout"] = *layout_override;
    if (preedit_override) preferences["tsf_preedit_style"] = *preedit_override;
    if (theme_override) preferences["candidate_theme"] = *theme_override;
    if (skin_override) preferences["candidate_skin"] = *skin_override;
    if (autocorrect_override) preferences["autocorrect"] = *autocorrect_override;
    if (frequency_mode_override) preferences["frequency"]["mode"] = *frequency_mode_override;
    const auto active_scheme = preferences.value("scheme", "quanpin");
    if (active_scheme == "quanpin" || active_scheme == "shuangpin") {
      if (helpcode_override) preferences[active_scheme + "_helpcode"]["enabled"] = *helpcode_override;
      if (helpcode_schema_override) preferences[active_scheme + "_helpcode"]["schema"] = *helpcode_schema_override;
      show_helpcode_in_candidate_window = preferences.value(
          active_scheme + "_helpcode", Json::object())
          .value("show_in_candidate_window", true);
    } else {
      show_helpcode_in_candidate_window = true;
    }
    clipboard_history_path = options.value("clipboard_history_path", std::string{});
    online_provider_socket = options.value("online_provider_socket", std::string{});
    if (online_provider_socket.empty()) {
      if (const auto *socket = g_getenv("MSIME_ONLINE_PROVIDER_SOCKET"))
        online_provider_socket = socket;
    }
    translation_provider_socket =
        options.value("translation_provider_socket", std::string{});
    if (translation_provider_socket.empty()) {
      if (const auto *socket = g_getenv("MSIME_TRANSLATION_PROVIDER_SOCKET"))
        translation_provider_socket = socket;
    }
    if (translation_provider_socket.empty())
      translation_provider_socket = online_provider_socket;
    voice_provider_socket = options.value("voice_provider_socket", std::string{});
    if (voice_provider_socket.empty()) {
      if (const auto *socket = g_getenv("MSIME_VOICE_PROVIDER_SOCKET"))
        voice_provider_socket = socket;
    }
    const auto voice_preferences = preferences.value("voice_input", Json::object());
    voice_enabled = voice_preferences.value("enabled", true);
    voice_language = voice_preferences.value("language", std::string("zh-cn"));
    voice_hotkey_ralt = voice_preferences.value("hotkey_ralt", true);
    voice_hotkey_ctrl_win = voice_preferences.value("hotkey_ctrl_win", false);
    voice_hotkey_rctrl_ralt = voice_preferences.value("hotkey_rctrl_ralt", false);
    voice_hotkey_hold_space_lock =
        voice_preferences.value("hotkey_hold_space_lock", true);
    voice_hotkey_ctrl_f9 = voice_preferences.value("hotkey_ctrl_f9", true);
    const auto keybindings = preferences.value("keybindings", Json::object());
    mode_shift_enabled = keybindings.value("switch_language_shift", true);
    mode_ctrl_enabled = keybindings.value("switch_language_ctrl", false);
    mode_ctrl_alt_space_enabled =
        keybindings.value("switch_language_ctrl_alt_space", true);
    character_set_shortcut_enabled =
        keybindings.value("toggle_character_set_ctrl_shift_f", true);
    traditional_output = traditional_output_override.value_or(
        preferences.value("traditional_chinese_output", false));
    cloud_candidates = cloud_candidates_override.value_or(
        preferences.value("cloud_candidates", true));
    if (english_override)
      options["preferences"]["mixed_input"]["english"] = *english_override;
    if (emoji_override)
      options["preferences"]["mixed_input"]["emoji"] = *emoji_override;
    if (kaomoji_override)
      options["preferences"]["mixed_input"]["kaomoji"] = *kaomoji_override;
    auto &local_modes = options["preferences"]["local_modes"];
    for (const auto &[key, value] : local_mode_overrides.items())
      local_modes[key] = value;
    if (private_input)
      options["preferences"]["learning"] = false;
    auto encoded = options.dump();
    auto bindings =
        msime::linux_host::NavigationBindings::read(options.at("preferences"));
    auto edge_binding = msime::linux_host::WordCharacterBinding::read(
        options.at("preferences"));
    view = response(msime_client_create(
        reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    session = view.at("session").get<uint64_t>();
    view = response(msime_client_set_character_width(session, fullwidth));
    const bool default_english =
        options.at("preferences").value("default_ime_mode", "chinese") == "english";
    english_mode = dedicated_english_override.value_or(default_english);
    view = response(msime_client_set_english_mode(session, english_mode));
    if (active_scheme == "quanpin" && nine_key_override)
      view = response(msime_client_set_nine_key_mode(session, *nine_key_override));
    chinese_punctuation = punctuation_override.value_or(
        options.at("preferences").value("chinese_punctuation", true));
    smart_punctuation = smart_punctuation_override.value_or(preferences.value("smart_punctuation", true));
    smart_punctuation_repeat = smart_repeat_override.value_or(preferences.value("smart_punctuation_repeat", true));
    paired_punctuation = options.at("preferences").value("paired_punctuation", true);
    punctuation_lock = preferences.value("punctuation_lock", "follow");
    if (punctuation_lock == "chinese")
      chinese_punctuation = true;
    else if (punctuation_lock == "english")
      chinese_punctuation = false;
    candidate_text_color =
        ::candidate_text_color(options.at("preferences"));
    candidate_background_color =
        ::candidate_background_color(options.at("preferences"));
    candidate_orientation = ::candidate_orientation(options.at("preferences"));
    preedit_style = ::preedit_style(options.at("preferences"));
    candidate_preedit_style =
        preferences.value("candidate_preedit_style", "pinyin");
    if (candidate_preedit_style != "empty")
      candidate_preedit_style = "pinyin";
    view = response(
        msime_client_set_chinese_punctuation(session, chinese_punctuation));
    navigation = bindings;
    word_character = edge_binding;
    if (word_character_override)
      word_character.enabled = *word_character_override;
  }
  void refresh_host_preferences(const Json &preferences) {
    mode_scope_global = preferences.value("ime_mode_scope", "app") == "global";
    if (mode_scope_global) {
      if (!global_input_enabled)
        global_input_enabled =
            preferences.value("default_ime_mode", "chinese") != "english";
      if (!session)
        input_enabled = *global_input_enabled;
    }
    navigation = msime::linux_host::NavigationBindings::read(preferences);
    word_character = msime::linux_host::WordCharacterBinding::read(preferences);
    if (word_character_override)
      word_character.enabled = *word_character_override;
    number_row_selection = number_row_override.value_or(
        preferences.value("number_row_selection", true));
    smart_punctuation = smart_punctuation_override.value_or(
        preferences.value("smart_punctuation", true));
    smart_punctuation_repeat = smart_repeat_override.value_or(
        preferences.value("smart_punctuation_repeat", true));
    paired_punctuation = paired_punctuation_override.value_or(
        preferences.value("paired_punctuation", true));
    punctuation_lock = punctuation_lock_override.value_or(
        preferences.value("punctuation_lock", "follow"));
    chinese_punctuation = punctuation_override.value_or(
        preferences.value("chinese_punctuation", true));
    if (punctuation_lock == "chinese")
      chinese_punctuation = true;
    else if (punctuation_lock == "english")
      chinese_punctuation = false;
    if (!smart_punctuation || !smart_punctuation_repeat || !paired_punctuation) {
      last_smart_punctuation = 0;
      last_smart_punctuation_time = 0;
      smart_punctuation_rejected = 0;
    }
    traditional_output = traditional_output_override.value_or(
        preferences.value("traditional_chinese_output", false));
    const bool next_cloud_candidates = cloud_candidates_override.value_or(
        preferences.value("cloud_candidates", true));
    if (next_cloud_candidates != cloud_candidates)
      invalidate_providers();
    cloud_candidates = next_cloud_candidates;
    auto display_preferences = preferences;
    if (layout_override)
      display_preferences["candidate_layout"] = *layout_override;
    if (theme_override)
      display_preferences["candidate_theme"] = *theme_override;
    if (skin_override)
      display_preferences["candidate_skin"] = *skin_override;
    candidate_text_color = ::candidate_text_color(display_preferences);
    candidate_background_color = ::candidate_background_color(display_preferences);
    candidate_orientation = ::candidate_orientation(display_preferences);
    preedit_style = preedit_override.value_or(::preedit_style(display_preferences));
    candidate_preedit_style = preferences.value("candidate_preedit_style", "pinyin");
    if (candidate_preedit_style != "empty")
      candidate_preedit_style = "pinyin";
    const auto active_scheme = scheme_override.value_or(
        preferences.value("scheme", "quanpin"));
    if (active_scheme == "quanpin" || active_scheme == "shuangpin")
      show_helpcode_in_candidate_window = preferences.value(
          active_scheme + "_helpcode", Json::object())
          .value("show_in_candidate_window", true);
    else
      show_helpcode_in_candidate_window = true;
    const auto voice = preferences.value("voice_input", Json::object());
    voice_enabled = voice.value("enabled", true);
    voice_language = voice.value("language", std::string("zh-cn"));
    voice_hotkey_ralt = voice.value("hotkey_ralt", true);
    voice_hotkey_ctrl_win = voice.value("hotkey_ctrl_win", false);
    voice_hotkey_rctrl_ralt = voice.value("hotkey_rctrl_ralt", false);
    voice_hotkey_hold_space_lock = voice.value("hotkey_hold_space_lock", true);
    voice_hotkey_ctrl_f9 = voice.value("hotkey_ctrl_f9", true);
    const auto keybindings = preferences.value("keybindings", Json::object());
    mode_shift_enabled = keybindings.value("switch_language_shift", true);
    mode_ctrl_enabled = keybindings.value("switch_language_ctrl", false);
    mode_ctrl_alt_space_enabled =
        keybindings.value("switch_language_ctrl_alt_space", true);
    character_set_shortcut_enabled =
        keybindings.value("toggle_character_set_ctrl_shift_f", true);
  }
  bool refresh_provider_sockets() {
    auto configured_socket = [](const Json &options, const char *key,
                                const char *environment) {
      auto socket = options.value(key, std::string{});
      if (socket.empty()) {
        if (const auto *fallback = g_getenv(environment))
          socket = fallback;
      }
      return socket;
    };
    const auto online = configured_socket(
        configured, "online_provider_socket", "MSIME_ONLINE_PROVIDER_SOCKET");
    const auto translation = [&] {
      auto socket = configured_socket(configured, "translation_provider_socket",
                                      "MSIME_TRANSLATION_PROVIDER_SOCKET");
      return socket.empty() ? online : socket;
    }();
    const auto voice = configured_socket(
        configured, "voice_provider_socket", "MSIME_VOICE_PROVIDER_SOCKET");
    const bool voice_changed = voice != voice_provider_socket;
    if (online != online_provider_socket ||
        translation != translation_provider_socket)
      invalidate_providers();
    online_provider_socket = online;
    translation_provider_socket = translation;
    voice_provider_socket = voice;
    return voice_changed;
  }
  void apply_session_overrides(Json &options) const {
    auto &preferences = options["preferences"];
    if (paired_punctuation_override)
      preferences["paired_punctuation"] = *paired_punctuation_override;
    if (punctuation_lock_override)
      preferences["punctuation_lock"] = *punctuation_lock_override;
    if (scheme_override)
      preferences["scheme"] = *scheme_override;
    if (shuangpin_profile_override)
      preferences["shuangpin_profile"] = *shuangpin_profile_override;
    if (candidate_page_size_override)
      preferences["candidate_page_size"] = *candidate_page_size_override;
    if (layout_override)
      preferences["candidate_layout"] = *layout_override;
    if (preedit_override)
      preferences["tsf_preedit_style"] = *preedit_override;
    if (theme_override)
      preferences["candidate_theme"] = *theme_override;
    if (skin_override)
      preferences["candidate_skin"] = *skin_override;
    if (autocorrect_override)
      preferences["autocorrect"] = *autocorrect_override;
    if (frequency_mode_override)
      preferences["frequency"]["mode"] = *frequency_mode_override;
    const auto active_scheme = preferences.value("scheme", "quanpin");
    if (active_scheme == "quanpin" || active_scheme == "shuangpin") {
      if (helpcode_override)
        preferences[active_scheme + "_helpcode"]["enabled"] = *helpcode_override;
      if (helpcode_schema_override)
        preferences[active_scheme + "_helpcode"]["schema"] = *helpcode_schema_override;
    }
    if (english_override)
      preferences["mixed_input"]["english"] = *english_override;
    if (emoji_override)
      preferences["mixed_input"]["emoji"] = *emoji_override;
    if (kaomoji_override)
      preferences["mixed_input"]["kaomoji"] = *kaomoji_override;
    auto &local_modes = preferences["local_modes"];
    for (const auto &[key, value] : local_mode_overrides.items())
      local_modes[key] = value;
    if (private_input)
      preferences["learning"] = false;
  }
};
bool script_conversion_applies(const Json &context) {
  return context.is_object() && context.value("scheme", 255) != 3 &&
         context.value("local_mode", "none") != "unicode";
}
std::string traditional_display(const State &s, const Json &context,
                                std::string text) {
  if (s.traditional_output && script_conversion_applies(context))
    text = msime_linux_simplified_to_traditional(text);
  return text;
}
std::vector<std::string> clipboard_items(const std::string &path) {
  std::vector<std::string> items;
  if (path.empty() || path.size() > 4096) return items;
  std::ifstream input{std::filesystem::path(path)};
  if (!input) return items;
  try {
    auto value = Json::parse(input);
    if (!value.is_array()) return items;
    for (const auto &entry : value) {
      if (items.size() == 8 || !entry.is_string()) break;
      auto text = entry.get<std::string>();
      if (text.size() > 4000) text.resize(4000);
      if (!text.empty()) items.push_back(std::move(text));
    }
  } catch (...) {}
  return items;
}
bool clipboard_remove_index(const std::string &path, size_t index) {
  if (path.empty() || path.size() > 4096)
    return false;
  const auto lock_path = path + ".lock";
  const int lock = open(lock_path.c_str(), O_CREAT | O_RDWR, 0600);
  if (lock < 0 || flock(lock, LOCK_EX) != 0) {
    if (lock >= 0)
      close(lock);
    return false;
  }
  bool removed = false;
  try {
    std::ifstream input{std::filesystem::path(path)};
    auto value = Json::parse(input);
    if (value.is_array() && index < value.size() && value.at(index).is_string()) {
      value.erase(value.begin() + index);
      const auto temporary = path + ".tmp." + std::to_string(getpid());
      std::ofstream output{std::filesystem::path(temporary), std::ios::trunc};
      if (output) {
        output << value.dump();
        output.close();
        std::error_code error;
        std::filesystem::permissions(
            temporary, std::filesystem::perms::owner_read |
                           std::filesystem::perms::owner_write,
            std::filesystem::perm_options::replace, error);
        std::filesystem::rename(temporary, path, error);
        if (!error)
          removed = true;
        else
          std::filesystem::remove(temporary, error);
      }
    }
  } catch (...) {
  }
  flock(lock, LOCK_UN);
  close(lock);
  return removed;
}
State &state(IBusEngine *engine);
void publish_mode(IBusEngine *engine, bool registration = false);
void sync_global_input_mode(IBusEngine *engine);
bool launch_desktop_panel(const char *panel) {
  const auto *command = g_getenv("MSIME_CLIENT_SETTINGS_COMMAND");
  if (!command || !*command)
    command = "msime-client-settings";
  gchar *argv[] = {const_cast<gchar *>(command), nullptr};
  gchar **environment = g_get_environ();
  environment = g_environ_setenv(environment, "MSIME_CLIENT_PANEL", panel, TRUE);
  GError *error = nullptr;
  const auto started = g_spawn_async(
      nullptr, argv, environment, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
      nullptr, &error);
  g_strfreev(environment);
  if (error)
    g_error_free(error);
  return started != FALSE;
}

IBusProperty *toolbar_property(IBusEngine *engine) {
  const auto &s = state(engine);
  const auto toolbar = configured.at("preferences").value(
      "floating_toolbar", Json::object());
  const bool available = toolbar.value("enabled", true) && s.focused && !s.blocked;
  auto items = ibus_prop_list_new();
  const auto append_toggle = [&](const char *name, const char *label,
                                 const char *hint, bool available, bool checked) {
    if (!available)
      return;
    ibus_prop_list_append(
        items, ibus_property_new(
                   name, PROP_TYPE_TOGGLE, ibus_text_new_from_static_string(label),
                   "", ibus_text_new_from_static_string(hint), TRUE, TRUE,
                   checked ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr));
  };
  const auto append_action = [&](const char *name, const char *label,
                                 const char *hint, bool available) {
    if (!available)
      return;
    ibus_prop_list_append(
        items, ibus_property_new(
                   name, PROP_TYPE_NORMAL, ibus_text_new_from_static_string(label),
                   "", ibus_text_new_from_static_string(hint), TRUE, TRUE,
                   PROP_STATE_UNCHECKED, nullptr));
  };
  append_toggle("Toolbar/InputMode", "中英文模式", "切换中文输入与直接输入",
                available, s.input_enabled);
  append_toggle("Toolbar/EnglishMode", "英文输入模式",
                "切换 Engine 的独立英文输入模式",
                available && toolbar.value("english_mode", true) &&
                    s.input_enabled && s.session,
                s.english_mode);
  append_toggle("Toolbar/Fullwidth", "全角字符", "切换 ASCII 全角或半角输出",
                available && toolbar.value("fullwidth", true), s.fullwidth);
  append_toggle("Toolbar/Punctuation", "中文标点", "切换中文或英文标点",
                available && toolbar.value("punctuation", true), s.chinese_punctuation);
  append_toggle("Toolbar/CharacterSet", "繁体输出", "切换简体或繁体输出",
                available && toolbar.value("character_set", true), s.traditional_output);
  append_action("Toolbar/Emoji", "表情与符号", "打开 Emoji、颜文字和符号面板",
                available && toolbar.value("emoji", true));
  append_action("Toolbar/ScreenKeyboard", "屏幕键盘", "打开屏幕键盘面板",
                available && toolbar.value("screen_keyboard", false));
  append_action("Toolbar/Settings", "设置", "打开水杉输入法设置",
                available && toolbar.value("settings", true));
  return ibus_property_new(
      "LinuxToolbar", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("工具栏"), "",
      ibus_text_new_from_static_string("Linux 原生输入法工具栏"), available, TRUE,
      PROP_STATE_UNCHECKED, items);
}

struct ClipboardTask {
  std::string path;
  uint64_t generation;
};
void clipboard_complete(GObject *source, GAsyncResult *result, gpointer);
void clipboard_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.clipboard_history_path.empty() || s.clipboard_loading || !s.focused ||
      s.blocked || !s.input_enabled || s.clipboard_loaded)
    return;
  s.clipboard_loading = true;
  auto task = g_task_new(G_OBJECT(engine), nullptr, clipboard_complete, nullptr);
  g_task_set_task_data(task,
                       new ClipboardTask{s.clipboard_history_path,
                                         s.clipboard_generation},
                       [](gpointer value) { delete static_cast<ClipboardTask *>(value); });
  g_task_run_in_thread(task, [](GTask *task, gpointer, gpointer data, GCancellable *) {
    const auto &request = *static_cast<ClipboardTask *>(data);
    g_task_return_pointer(task, new std::vector<std::string>(clipboard_items(request.path)),
                          [](gpointer value) {
                            delete static_cast<std::vector<std::string> *>(value);
                          });
  });
  g_object_unref(task);
}
std::string fullwidth_text(const std::string &text) {
  std::string result;
  for (unsigned char c : text) {
    if (c >= 0x21 && c <= 0x7e) {
      const uint32_t code = c + 0xfee0;
      result.push_back(static_cast<char>(0xe0 | (code >> 12)));
      result.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3f)));
      result.push_back(static_cast<char>(0x80 | (code & 0x3f)));
    } else if (c == ' ') {
      result.append("\xe3\x80\x80");
    } else {
      // Preserve complete UTF-8 sequences byte-for-byte.
      result.push_back(static_cast<char>(c));
    }
  }
  return result;
}
std::optional<guint> candidate_text_color(const Json &preferences) {
  const auto value = preferences.value("candidate_text_color", Json(nullptr));
  if (!value.is_string())
    return std::nullopt;
  const auto hex = value.get<std::string>();
  if (hex.size() != 7 || hex.front() != '#')
    return std::nullopt;
  guint color = 0;
  for (size_t index = 1; index < hex.size(); ++index) {
    const auto c = static_cast<unsigned char>(hex[index]);
    guint digit = 0;
    if (c >= '0' && c <= '9')
      digit = c - '0';
    else if (c >= 'a' && c <= 'f')
      digit = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F')
      digit = c - 'A' + 10;
    else
      return std::nullopt;
    color = (color << 4) | digit;
  }
  return color;
}
std::optional<guint> candidate_background_color(const Json &preferences) {
  const auto skin = preferences.value("candidate_skin", "fluent");
  const auto theme = preferences.value("candidate_theme", "follow");
  const bool dark = theme == "dark";
  if (skin == "wechat") return dark ? 0x163c2cu : 0xe8f5e9u;
  if (skin == "graphite") return dark ? 0x2f3437u : 0xf1f3f4u;
  if (skin == "willow_green") return dark ? 0x244437u : 0xf1f8eeu;
  if (theme == "dark") return 0x202124u;
  if (theme == "light") return 0xffffffu;
  return std::nullopt;
}
IBusOrientation candidate_orientation(const Json &preferences) {
  return preferences.value("candidate_layout", "vertical") == "horizontal"
             ? IBUS_ORIENTATION_HORIZONTAL
             : IBUS_ORIENTATION_VERTICAL;
}
std::string preedit_style(const Json &preferences) {
  const auto style = preferences.value("tsf_preedit_style", "raw");
  return style == "pinyin" || style == "empty" ? style : "raw";
}
const char *smart_punctuation_pair(char value) {
  switch (value) {
  case ',': return "，"; case '.': return "。"; case ';': return "；";
  case ':': return "："; case '!': return "！"; case '?': return "？";
  case '(': return "（"; case ')': return "）"; case '[': return "【";
  case ']': return "】"; case '{': return "｛"; case '}': return "｝";
  case '<': return "〈"; case '>': return "〉"; default: return nullptr;
  }
}
const char *paired_punctuation_closing(std::string_view text) {
  for (const auto &[opening, closing] : {
           std::pair<std::string_view, const char *> {"（", "）"},
           {"【", "】"},
           {"《", "》"},
           {"〈", "〉"}}) {
    if (text.size() >= opening.size() &&
        text.compare(text.size() - opening.size(), opening.size(), opening) == 0)
      return closing;
  }
  return nullptr;
}
enum class PunctuationPairMode {
  None,
  Bracket,
  Brace,
  DoubleQuote,
  SingleQuote
};
bool normalize_punctuation_pair(std::string &text, PunctuationPairMode mode) {
  if (mode == PunctuationPairMode::None)
    return false;
  if (mode == PunctuationPairMode::Brace) {
    if (!text.empty() && text.back() == '{') {
      text.push_back('}');
      return true;
    }
    return false;
  }
  if (mode == PunctuationPairMode::Bracket) {
    if (const auto *closing = paired_punctuation_closing(text)) {
      text += closing;
      return true;
    }
    return false;
  }
  const std::string_view opening =
      mode == PunctuationPairMode::DoubleQuote ? "“" : "‘";
  const std::string_view closing =
      mode == PunctuationPairMode::DoubleQuote ? "”" : "’";
  for (const auto suffix : {opening, closing}) {
    if (text.size() < suffix.size() ||
        text.compare(text.size() - suffix.size(), suffix.size(), suffix) != 0)
      continue;
    text.erase(text.size() - suffix.size());
    text += opening;
    text += closing;
    return true;
  }
  return false;
}
bool is_smart_punctuation_key(guint key) {
  return key == IBUS_comma || key == IBUS_period || key == IBUS_colon;
}
bool is_ascii_alphanumeric(unsigned char value) {
  return (value >= '0' && value <= '9') ||
         (value >= 'A' && value <= 'Z') ||
         (value >= 'a' && value <= 'z');
}
bool smart_punctuation_preceded_by_ascii_alphanumeric(const State &s) {
  // A highlighted candidate is the preceding text for punctuation finishing
  // an active composition. This mirrors the Windows TSF path, while IBus
  // surrounding text supplies the document character for a pure punctuation
  // input.
  if (s.view.is_object()) {
    const auto candidates = s.view.value("candidates", Json::array());
    if (candidates.is_array()) {
      for (const auto &candidate : candidates) {
        if (!candidate.is_object() || !candidate.value("highlighted", false))
          continue;
        const auto text = candidate.value("text", std::string{});
        if (text.empty())
          break;
        const auto last = static_cast<unsigned char>(text.back());
        return last < 0x80 && is_ascii_alphanumeric(last);
      }
    }
  }
  const auto &surrounding = s.surrounding_text;
  const auto cursor = std::min<std::size_t>(s.surrounding_cursor, surrounding.size());
  if (cursor == 0)
    return false;
  const auto value = static_cast<unsigned char>(surrounding[cursor - 1]);
  // A UTF-8 continuation byte means the preceding code point is non-ASCII.
  return value < 0x80 && is_ascii_alphanumeric(value);
}
constexpr gint64 kSmartPunctuationRepeatIntervalUs = 2 * G_USEC_PER_SEC;

struct OnlineTask {
  uint64_t session;
  uint64_t epoch;
  std::string query;
  std::string socket;
};
struct TranslationTask {
  uint64_t session;
  uint64_t epoch;
  std::string query;
  std::string socket;
};
bool apply(IBusEngine *engine, char *raw,
           PunctuationPairMode pair_mode = PunctuationPairMode::None);
void render(IBusEngine *engine, const Json &view);
void translation_complete(GObject *source, GAsyncResult *result, gpointer);
bool translation_request_is_stale(IBusEngine *engine, const std::string &encoded) {
  try {
    const auto request = Json::parse(encoded);
    const auto generation = request.at("generation").get<uint64_t>();
    auto &s = state(engine);
    if (!s.session)
      return false;
    const auto current = response(msime_client_translation_query(s.session));
    return current.is_object() &&
           current.value("generation", generation) != generation;
  } catch (...) {
    return false;
  }
}
void translation_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.translation_provider_socket.empty() || s.translation_loading || !s.session ||
      !s.focused || s.blocked || !s.input_enabled ||
      s.candidate_orientation != IBUS_ORIENTATION_VERTICAL ||
      !s.view.value("candidates", Json::array()).size())
    return;
  try {
    auto query = response(msime_client_translation_query(s.session));
    if (query.is_null() || !query.is_object()) return;
    auto *task_data = new TranslationTask{s.session, s.provider_epoch, query.dump(), s.translation_provider_socket};
    s.translation_loading = true;
    auto task = g_task_new(G_OBJECT(engine), nullptr, translation_complete, nullptr);
    g_task_set_task_data(task, task_data, [](gpointer value) { delete static_cast<TranslationTask *>(value); });
    g_task_run_in_thread(task, [](GTask *task, gpointer, gpointer data, GCancellable *) {
      auto &request = *static_cast<TranslationTask *>(data);
      auto *raw = msime_client_translation_provider_request(
          reinterpret_cast<const uint8_t *>(request.query.data()), request.query.size(),
          reinterpret_cast<const uint8_t *>(request.socket.data()), request.socket.size());
      g_task_return_pointer(task, raw, [](gpointer value) { msime_client_string_free(static_cast<char *>(value)); });
    });
    g_object_unref(task);
  } catch (...) { s.translation_loading = false; }
}
void online_complete(GObject *source, GAsyncResult *result, gpointer);
bool online_request_is_stale(IBusEngine *engine, const std::string &encoded) {
  try {
    const auto request = Json::parse(encoded);
    const auto generation = request.at("generation").get<uint64_t>();
    auto &s = state(engine);
    if (!s.session)
      return false;
    const auto current = response(msime_client_online_query(s.session));
    return current.is_object() &&
           current.value("generation", generation) != generation;
  } catch (...) {
    return false;
  }
}
void online_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_provider_socket.empty() || s.online_loading || !s.session ||
      !s.focused || s.blocked || !s.input_enabled)
    return;
  try {
    auto query = response(msime_client_online_query(s.session));
    if (query.is_object())
      query["cloud_candidates"] = s.cloud_candidates;
    if (!query.is_object() ||
        (!s.cloud_candidates && !query.value("ai_eligible", false)) ||
        (s.cloud_candidates &&
         !(query.value("cloud_eligible", false) || query.value("ai_eligible", false))))
      return;
    auto *task_data = new OnlineTask{s.session, s.provider_epoch, query.dump(), s.online_provider_socket};
    s.online_loading = true;
    auto task = g_task_new(G_OBJECT(engine), nullptr, online_complete, nullptr);
    g_task_set_task_data(task, task_data, [](gpointer value) {
      delete static_cast<OnlineTask *>(value);
    });
    g_task_run_in_thread(task, [](GTask *task, gpointer, gpointer data, GCancellable *) {
      auto &request = *static_cast<OnlineTask *>(data);
      auto *raw = msime_client_online_provider_request(
          reinterpret_cast<const uint8_t *>(request.query.data()), request.query.size(),
          reinterpret_cast<const uint8_t *>(request.socket.data()), request.socket.size());
      g_task_return_pointer(task, raw, [](gpointer value) {
        msime_client_string_free(static_cast<char *>(value));
      });
    });
    g_object_unref(task);
  } catch (...) {
    s.online_loading = false;
  }
}
void translation_complete(GObject *source, GAsyncResult *result, gpointer) {
  auto engine = IBUS_ENGINE(source);
  auto &s = state(engine);
  std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
      static_cast<char *>(g_task_propagate_pointer(G_TASK(result), nullptr)),
      msime_client_string_free);
  const auto *request = static_cast<const TranslationTask *>(
      g_task_get_task_data(G_TASK(result)));
  if (!request || request->session != s.session || request->epoch != s.provider_epoch)
    return;
  s.translation_loading = false;
  if (!s.session || !s.focused || s.blocked || !s.input_enabled)
    return;
  if (translation_request_is_stale(engine, request->query)) {
    translation_schedule(engine);
    return;
  }
  if (!raw)
    return;
  try {
    const auto document = Json::parse(raw.get());
    if (!document.value("ok", false)) return;
    const auto value = document.at("value");
    if (!value.is_object()) return;
    const auto generation = Json::parse(request->query).at("generation").get<uint64_t>();
    const auto encoded = value.at("translations").dump();
    auto applied = response(msime_client_apply_translations(
        s.session, generation, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    s.view = applied.at("view");
    render(engine, s.view);
  } catch (...) {}
}
void online_complete(GObject *source, GAsyncResult *result, gpointer) {
  auto engine = IBUS_ENGINE(source);
  auto &s = state(engine);
  std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
      static_cast<char *>(g_task_propagate_pointer(G_TASK(result), nullptr)),
      msime_client_string_free);
  const auto *request = static_cast<const OnlineTask *>(
      g_task_get_task_data(G_TASK(result)));
  if (!request || request->session != s.session || request->epoch != s.provider_epoch)
    return;
  s.online_loading = false;
  if (!s.session || !s.focused || s.blocked || !s.input_enabled)
    return;
  if (online_request_is_stale(engine, request->query)) {
    online_schedule(engine);
    return;
  }
  if (!raw)
    return;
  try {
    const auto document = Json::parse(raw.get());
    if (!document.value("ok", false)) return;
    const auto value = document.at("value");
    const auto candidate = value.value("text", std::string{});
    if (candidate.empty()) return;
    const auto source = static_cast<uint8_t>(value.value("source", 0));
    if (!s.cloud_candidates && source == 0) return;
    auto applied = response(msime_client_apply_online_candidate(
        s.session, reinterpret_cast<const uint8_t *>(request->query.data()), request->query.size(),
        reinterpret_cast<const uint8_t *>(candidate.data()), candidate.size(),
        source));
    s.view = applied.at("view");
    render(engine, s.view);
    translation_schedule(engine);
  } catch (...) {}
}
} // namespace

struct MsimePreviewEngine {
  IBusEngine parent;
  State *state;
};
struct MsimePreviewEngineClass {
  IBusEngineClass parent;
};
G_DEFINE_TYPE(MsimePreviewEngine, msime_preview_engine, IBUS_TYPE_ENGINE)

namespace {
State &state(IBusEngine *engine) {
  return *reinterpret_cast<MsimePreviewEngine *>(engine)->state;
}
void clipboard_complete(GObject *source, GAsyncResult *result, gpointer) {
  auto self = reinterpret_cast<MsimePreviewEngine *>(source);
  if (!self->state)
    return;
  auto &s = *self->state;
  s.clipboard_loading = false;
  auto request = static_cast<ClipboardTask *>(
      g_task_get_task_data(G_TASK(result)));
  // Always propagate the task result, including stale completions, so its
  // destroy notifier releases the worker allocation.
  auto *items = static_cast<std::vector<std::string> *>(
      g_task_propagate_pointer(G_TASK(result), nullptr));
  if (request->generation != s.clipboard_generation || !s.focused || s.blocked ||
      request->path != s.clipboard_history_path) {
    delete items;
    return;
  }
  if (!items)
    return;
  s.clipboard_items_cache = std::move(*items);
  s.clipboard_loaded = true;
  delete items;
  publish_mode(IBUS_ENGINE(source));
}
std::string candidate_action_name(const char *action, const Json &id) {
  return std::string(action) + "/" + std::to_string(id.at("session").get<uint64_t>()) +
         "/" + std::to_string(id.at("generation").get<uint64_t>()) +
         "/" + std::to_string(id.at("index").get<size_t>());
}
std::string nine_key_spelling_action_name(uint64_t session, uint64_t generation,
                                          size_t index) {
  return "NineKeySpelling/" + std::to_string(session) + "/" +
         std::to_string(generation) + "/" + std::to_string(index);
}
IBusProperty *nine_key_spellings(IBusEngine *engine) {
  const auto &s = state(engine);
  auto menu = ibus_prop_list_new();
  const auto spellings = s.view.is_object()
                             ? s.view.value("nine_key_spellings", Json::array())
                             : Json::array();
  const bool available = s.session && s.focused && !s.blocked && s.input_enabled &&
                         s.view.value("nine_key", false) && spellings.is_array();
  bool has_items = false;
  if (available) {
    const auto generation = s.view.value("generation", uint64_t{0});
    for (size_t index = 0; index < spellings.size(); ++index) {
      if (!spellings.at(index).is_string())
        continue;
      auto spelling = spellings.at(index).get<std::string>();
      if (spelling.empty() || spelling.size() > 64)
        continue;
      const auto name = nine_key_spelling_action_name(s.session, generation, index);
      const auto label = std::to_string(index + 1) + ". " + spelling;
      ibus_prop_list_append(menu, ibus_property_new(
          name.c_str(), PROP_TYPE_NORMAL, ibus_text_new_from_string(label.c_str()),
          "", ibus_text_new_from_static_string("选择九键拼音"), TRUE, FALSE,
          PROP_STATE_UNCHECKED, nullptr));
      has_items = true;
    }
  }
  const bool enabled = available && has_items;
  return ibus_property_new(
      "NineKeySpellings", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("九键拼音"), "",
      ibus_text_new_from_static_string("选择九键数字对应的拼音"), enabled, TRUE,
      PROP_STATE_UNCHECKED, menu);
}
IBusProperty *candidate_actions(IBusEngine *engine) {
  const auto &s = state(engine);
  auto items = ibus_prop_list_new();
  const auto candidates = s.view.is_object()
                              ? s.view.value("candidates", Json::array())
                              : Json::array();
  const auto scheme = s.view.is_object() ? s.view.value("scheme", 255) : 255;
  bool editable_candidates = false;
  for (size_t index = 0; index < candidates.size(); ++index) {
    const auto &candidate = candidates.at(index);
    if (!candidate.is_object() || !candidate.contains("id") ||
        !candidate.at("id").is_object())
      continue;
    const auto &id = candidate.at("id");
    if (!id.contains("session") || !id.contains("generation") || !id.contains("index") ||
        !id.at("session").is_number_unsigned() || !id.at("generation").is_number_unsigned() ||
        !id.at("index").is_number_unsigned())
      continue;
    // Engine only persists operations for local dictionary and English
    // dictionary entries. Dynamic, local-mode and Japanese candidates have
    // no user-dictionary identity to mutate.
    const auto source = candidate.value("source", 0);
    if (scheme == 3 || (source != 0 && source != 1 && source != 4))
      continue;
    editable_candidates = true;
    const auto slot = index + 1;
    for (const auto &[action, label] : {std::pair{"CandidatePin", "固定候选"},
                                       std::pair{"CandidateRemove", "删除候选"},
                                       std::pair{"CandidateFix1", "固定到 1"},
                                       std::pair{"CandidateFix2", "固定到 2"},
                                       std::pair{"CandidateFix3", "固定到 3"},
                                       std::pair{"CandidateFix4", "固定到 4"},
                                       std::pair{"CandidateFix5", "固定到 5"},
                                       std::pair{"CandidateClear", "取消固定"}}) {
      const auto name = candidate_action_name(action, candidate.at("id"));
      const auto title = std::string(label) + " " + std::to_string(slot);
      ibus_prop_list_append(items, ibus_property_new(
          name.c_str(), PROP_TYPE_NORMAL, ibus_text_new_from_string(title.c_str()), "",
          ibus_text_new_from_static_string("操作当前页候选"), TRUE, TRUE,
          PROP_STATE_UNCHECKED, nullptr));
    }
  }
  return ibus_property_new("CandidateActions", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选操作"), "",
      ibus_text_new_from_static_string("固定或删除当前页候选"),
      s.session && s.focused && !s.blocked && s.input_enabled && editable_candidates,
      TRUE, PROP_STATE_UNCHECKED, items);
}
void publish_mode(IBusEngine *engine, bool registration) {
  auto &s = state(engine);
  clipboard_schedule(engine);
  auto toolbar = toolbar_property(engine);
  const bool japanese_scheme = s.scheme_override
                                   ? *s.scheme_override == "japanese"
                                   : configured.at("preferences").value("scheme", "") == "japanese";
  const bool english_candidates = s.english_override.value_or(
      configured.at("preferences").at("mixed_input").value("english", false));
  const bool emoji_candidates = s.emoji_override.value_or(
      configured.at("preferences").at("mixed_input").value("emoji", false));
  const bool kaomoji_candidates = s.kaomoji_override.value_or(
      configured.at("preferences").at("mixed_input").value("kaomoji", false));
  const bool autocorrect = s.autocorrect_override.value_or(
      configured.at("preferences").value("autocorrect", true));
  const auto active_scheme = s.scheme_override.value_or(
      configured.at("preferences").value("scheme", "quanpin"));
  const bool nine_key = active_scheme == "quanpin" &&
                        s.view.value("nine_key", false);
  const bool helpcode = (active_scheme == "quanpin" || active_scheme == "shuangpin") &&
      s.helpcode_override.value_or(configured.at("preferences")
          .value(active_scheme + "_helpcode", Json::object()).value("enabled", true));
  const auto layout = s.layout_override.value_or(
      configured.at("preferences").value("candidate_layout", "vertical"));
  const auto preedit = s.preedit_override.value_or(
      configured.at("preferences").value("tsf_preedit_style", "raw"));
  const auto theme = s.theme_override.value_or(
      configured.at("preferences").value("candidate_theme", "follow"));
  const auto skin = s.skin_override.value_or(
      configured.at("preferences").value("candidate_skin", "fluent"));
  auto property = ibus_property_new(
      "InputMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("输入法模式"), "",
      ibus_text_new_from_static_string(s.input_enabled ? "使用当前输入方案"
                                                       : "直接输入（不转换）"),
      s.focused && !s.blocked, TRUE,
      s.input_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_property_set_symbol(
      property, ibus_text_new_from_static_string(s.input_enabled ? "文" : "A"));
  auto voice = ibus_property_new(
      "VoiceInput", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("语音输入"), "",
      ibus_text_new_from_static_string("通过用户管理的 Linux 语音服务录音并识别"),
      s.focused && !s.blocked && s.input_enabled && s.voice_enabled &&
          !s.voice_provider_socket.empty(),
      TRUE, s.voice_active ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto cloud = ibus_property_new(
      "CloudCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("云联想"), "",
      ibus_text_new_from_static_string("通过用户管理的 provider 请求云候选"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !s.online_provider_socket.empty(),
      TRUE, s.cloud_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto punctuation = ibus_property_new(
      "Punctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("切换中文或英文标点"),
      s.focused && !s.blocked && s.input_enabled && s.session, TRUE,
      s.chinese_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto smart_punctuation = ibus_property_new(
      "SmartPunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("智能标点"), "",
      ibus_text_new_from_static_string("按上下文选择标点形式"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      s.smart_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto smart_repeat = ibus_property_new(
      "SmartPunctuationRepeat", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("重复标点转中文"), "",
      ibus_text_new_from_static_string("短时间重复输入 ASCII 标点时替换为中文标点"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      s.smart_punctuation_repeat ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto paired = ibus_property_new(
      "PairedPunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("成对标点"), "",
      ibus_text_new_from_static_string("输入成对引号和括号"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      s.paired_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto punctuation_lock = ibus_property_new(
      "PunctuationLock", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("标点锁定"), "",
      ibus_text_new_from_static_string("跟随输入模式或固定中文/英文标点"),
      s.focused && !s.blocked && s.input_enabled, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto punctuation_lock_menu = ibus_prop_list_new();
  for (const auto &[value, label] : {std::pair{"follow", "跟随"},
                                     std::pair{"chinese", "固定中文"},
                                     std::pair{"english", "固定英文"}}) {
    auto item = ibus_property_new(
        (std::string("PunctuationLock/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择标点锁定策略"), TRUE, TRUE,
        s.punctuation_lock == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(punctuation_lock_menu, item);
  }
  ibus_property_set_sub_props(punctuation_lock, punctuation_lock_menu);
  auto character_mode = ibus_property_new(
      "CharacterMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("全角字符"), "",
      ibus_text_new_from_static_string("切换 ASCII 全角或半角输出"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      s.fullwidth ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto traditional = ibus_property_new(
      "TraditionalOutput", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("繁体输出"), "",
      ibus_text_new_from_static_string("将中文候选和上屏文本转换为繁体"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !japanese_scheme,
      TRUE, s.traditional_output ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto english = ibus_property_new(
      "EnglishCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充英文候选"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      english_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto english_mode = ibus_property_new(
      "EnglishMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文输入模式"), "",
      ibus_text_new_from_static_string("切换 Engine 的独立英文输入模式（Ctrl+Shift+E）"),
      s.focused && !s.blocked && s.input_enabled && s.session, TRUE,
      s.english_mode ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto autocorrect_property = ibus_property_new(
      "Autocorrect", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("拼音自动纠错"), "",
      ibus_text_new_from_static_string("启用拼音输入自动纠错"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      autocorrect ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto helpcode_property = ibus_property_new(
      "Helpcode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("辅助码"), "",
      ibus_text_new_from_static_string("启用候选辅助码提示"),
      s.focused && !s.blocked && s.input_enabled &&
          (active_scheme == "quanpin" || active_scheme == "shuangpin"), TRUE,
      helpcode ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto helpcode_schema = ibus_property_new(
      "HelpcodeSchema", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("辅助码方案"), "",
      ibus_text_new_from_static_string("选择辅助码编码方案"),
      s.focused && !s.blocked && s.input_enabled &&
          (active_scheme == "quanpin" || active_scheme == "shuangpin"), TRUE,
      PROP_STATE_UNCHECKED, nullptr);
  auto helpcode_schema_menu = ibus_prop_list_new();
  const auto schema = s.helpcode_schema_override.value_or(
      configured.at("preferences").value(active_scheme + "_helpcode", Json::object())
          .value("schema", "ziranma"));
  for (const auto &[value, label] : {std::pair{"lantian", "蓝天"},
                                     std::pair{"ziranma", "自然码"},
                                     std::pair{"shouyou2_0", "搜狗 2.0"},
                                     std::pair{"shouyouplus", "搜狗 Plus"},
                                     std::pair{"xiaohe", "小鹤"}}) {
    auto item = ibus_property_new(
        (std::string("HelpcodeSchema/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("切换辅助码方案"), TRUE, TRUE,
        schema == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(helpcode_schema_menu, item);
  }
  ibus_property_set_sub_props(helpcode_schema, helpcode_schema_menu);
  auto emoji = ibus_property_new(
      "EmojiCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("Emoji 候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充 Emoji 候选"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      emoji_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto kaomoji = ibus_property_new(
      "KaomojiCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("颜文字候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充颜文字候选"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      kaomoji_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto clipboard = ibus_property_new(
      "ClipboardHistory", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("剪贴板历史"), "",
      ibus_text_new_from_static_string("提交最近一条历史文本"),
      s.focused && !s.blocked && s.input_enabled && !s.clipboard_history_path.empty(),
      TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto clipboard_menu = ibus_prop_list_new();
  const auto &items = s.clipboard_items_cache;
  for (size_t index = 0; index < items.size(); ++index) {
    const auto label = std::to_string(index + 1) + ". " + items[index].substr(0, 48);
    auto item = ibus_property_new(
        (std::string("ClipboardHistory/") + std::to_string(index)).c_str(),
        PROP_TYPE_NORMAL, ibus_text_new_from_string(label.c_str()), "",
        ibus_text_new_from_static_string("提交历史文本"), TRUE, FALSE,
        PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(clipboard_menu, item);
    auto remove = ibus_property_new(
        (std::string("ClipboardHistory/Remove/") + std::to_string(index)).c_str(),
        PROP_TYPE_NORMAL,
        ibus_text_new_from_string((std::string("删除 ") + std::to_string(index + 1)).c_str()),
        "", ibus_text_new_from_static_string("删除这一条历史文本"), TRUE, FALSE,
        PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(clipboard_menu, remove);
  }
  auto clear_clipboard = ibus_property_new(
      "ClipboardHistory/Clear", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string("清空历史"), "",
      ibus_text_new_from_static_string("删除本地剪贴板历史文件"),
      !items.empty(), FALSE, PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(clipboard_menu, clear_clipboard);
  ibus_property_set_sub_props(clipboard, clipboard_menu);
  auto layout_property = ibus_property_new(
      "CandidateLayout", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选布局"), "",
      ibus_text_new_from_static_string("当前焦点会话的候选排列方向"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto layout_menu = ibus_prop_list_new();
  auto vertical = ibus_property_new(
      "CandidateLayout/Vertical", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("竖排"), "",
      ibus_text_new_from_static_string("竖直排列候选"), TRUE, TRUE,
      layout == "vertical" ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto horizontal = ibus_property_new(
      "CandidateLayout/Horizontal", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("横排"), "",
      ibus_text_new_from_static_string("水平排列候选"), TRUE, TRUE,
      layout == "horizontal" ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  ibus_prop_list_append(layout_menu, vertical);
  ibus_prop_list_append(layout_menu, horizontal);
  ibus_property_set_sub_props(layout_property, layout_menu);
  auto page_size_property = ibus_property_new(
      "CandidatePageSize", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选数量"), "",
      ibus_text_new_from_static_string("选择每页显示的候选数量"),
      s.focused && !s.blocked && s.input_enabled, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto page_size_menu = ibus_prop_list_new();
  const auto page_size = s.candidate_page_size_override.value_or(
      configured.at("preferences").value("candidate_page_size", 5));
  for (uint8_t value = 1; value <= 9; ++value) {
    auto item = ibus_property_new(
        (std::string("CandidatePageSize/") + std::to_string(value)).c_str(),
        PROP_TYPE_RADIO, ibus_text_new_from_string(std::to_string(value).c_str()),
        "", ibus_text_new_from_static_string("设置候选页大小"), TRUE, TRUE,
        page_size == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(page_size_menu, item);
  }
  ibus_property_set_sub_props(page_size_property, page_size_menu);
  auto frequency_property = ibus_property_new(
      "FrequencyMode", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("词频调节"), "",
      ibus_text_new_from_static_string("选择学习词频调节策略"),
      s.focused && !s.blocked && s.input_enabled, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto frequency_menu = ibus_prop_list_new();
  const auto frequency = s.frequency_mode_override.value_or(
      configured.at("preferences").value("frequency", Json::object())
          .value("mode", "promote"));
  for (const auto &[value, label] : {std::pair{"disabled", "禁用"},
                                     std::pair{"pin", "固定"},
                                     std::pair{"halve", "减半"},
                                     std::pair{"linear", "线性"},
                                     std::pair{"promote", "提升"}}) {
    auto item = ibus_property_new(
        (std::string("FrequencyMode/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("设置词频调节模式"), TRUE, TRUE,
        frequency == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(frequency_menu, item);
  }
  ibus_property_set_sub_props(frequency_property, frequency_menu);
  auto number_row_property = ibus_property_new(
      "NumberRowSelection", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("数字选词"), "",
      ibus_text_new_from_static_string("使用数字键选择候选词"),
      s.focused && !s.blocked && s.input_enabled && !nine_key, TRUE,
      s.number_row_selection && !nine_key ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto nine_key_property = ibus_property_new(
      "NineKey", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("九键输入"), "",
      ibus_text_new_from_static_string("使用数字键输入全拼并选择拼音候选"),
      s.focused && !s.blocked && s.input_enabled && active_scheme == "quanpin",
      TRUE, nine_key ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto nine_key_spellings_property = nine_key_spellings(engine);
  auto local_modes_property = ibus_property_new(
      "LocalModes", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("本地输入模式"), "",
      ibus_text_new_from_static_string("启用或停用当前会话的本地快捷输入模式"),
      s.focused && !s.blocked && s.input_enabled, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto local_modes_menu = ibus_prop_list_new();
  const auto configured_local_modes = configured.at("preferences").value(
      "local_modes", Json::object());
  const std::pair<const char *, const char *> local_mode_options[] = {
      {"unicode", "Unicode（U 模式）"},
      {"date_time", "日期时间（T 模式）"},
      {"quick_phrase", "快捷短语（K 模式）"},
      {"emoji", "Emoji（E 模式）"},
      {"kaomoji", "颜文字（M 模式）"},
      {"super_jianpin", "超级简拼（J 模式）"},
      {"temporary_english", "临时英文（Y 模式）"},
      {"temporary_japanese", "临时日文（R 模式）"}};
  for (const auto &[key, label] : local_mode_options) {
    const bool enabled = local_mode_overrides.contains(key)
                             ? local_mode_overrides.at(key).get<bool>()
                             : configured_local_modes.value(key, true);
    auto item = ibus_property_new(
        (std::string("LocalModes/") + key).c_str(), PROP_TYPE_TOGGLE,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("当前会话本地快捷输入模式"),
        s.focused && !s.blocked && s.input_enabled, TRUE,
        enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(local_modes_menu, item);
  }
  ibus_property_set_sub_props(local_modes_property, local_modes_menu);
  auto word_character_property = ibus_property_new(
      "WordCharacter", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("以词定字"), "",
      ibus_text_new_from_static_string("使用减号/等号或方括号选择词语首末汉字"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      s.word_character.enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto preedit_property = ibus_property_new(
      "PreeditStyle", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("预编辑显示"), "",
      ibus_text_new_from_static_string("当前焦点会话的预编辑显示方式"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto preedit_menu = ibus_prop_list_new();
  const std::pair<const char *, const char *> preedit_options[] = {
      {"raw", "编码"}, {"pinyin", "拼音"}, {"empty", "隐藏"}};
  for (const auto &[value, label] : preedit_options) {
    auto item = ibus_property_new(
        (std::string("PreeditStyle/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择预编辑显示方式"), TRUE, TRUE,
        preedit == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(preedit_menu, item);
  }
  ibus_property_set_sub_props(preedit_property, preedit_menu);
  auto theme_property = ibus_property_new(
      "CandidateTheme", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选主题"), "",
      ibus_text_new_from_static_string("当前焦点会话的候选背景主题"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto theme_menu = ibus_prop_list_new();
  const std::pair<const char *, const char *> theme_options[] = {
      {"follow", "跟随系统"}, {"light", "浅色"}, {"dark", "深色"}};
  for (const auto &[value, label] : theme_options) {
    auto item = ibus_property_new(
        (std::string("CandidateTheme/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择候选主题"), TRUE, TRUE,
        theme == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(theme_menu, item);
  }
  ibus_property_set_sub_props(theme_property, theme_menu);
  auto skin_property = ibus_property_new(
      "CandidateSkin", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选皮肤"), "",
      ibus_text_new_from_static_string("选择候选窗口内置皮肤"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto skin_menu = ibus_prop_list_new();
  const std::pair<const char *, const char *> skin_options[] = {
      {"fluent", "Fluent"}, {"wechat", "微信绿"},
      {"graphite", "Graphite"}, {"willow_green", "杨柳青"}};
  for (const auto &[value, label] : skin_options) {
    auto item = ibus_property_new(
        (std::string("CandidateSkin/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择候选窗口内置皮肤"), TRUE, TRUE,
        skin == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(skin_menu, item);
  }
  ibus_property_set_sub_props(skin_property, skin_menu);
  auto scheme = ibus_property_new(
      "Scheme", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("输入方案"), "",
      ibus_text_new_from_static_string("当前焦点会话的中文或日文方案"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto scheme_menu = ibus_prop_list_new();
  auto chinese = ibus_property_new(
      "Scheme/Chinese", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("中文"), "",
      ibus_text_new_from_static_string("使用当前中文方案"), TRUE, TRUE,
      japanese_scheme ? PROP_STATE_UNCHECKED : PROP_STATE_CHECKED, nullptr);
  auto japanese = ibus_property_new(
      "Scheme/Japanese", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("日文"), "",
      ibus_text_new_from_static_string("使用日语罗马字方案"), TRUE, TRUE,
      japanese_scheme ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(scheme_menu, chinese);
  ibus_prop_list_append(scheme_menu, japanese);
  const auto active_chinese_scheme = s.scheme_override.value_or(
      configured.at("preferences").value("last_chinese_scheme", std::string("quanpin")));
  for (const auto &[value, label] : {std::pair{"quanpin", "全拼"},
                                     std::pair{"shuangpin", "双拼"},
                                     std::pair{"wubi", "五笔"}}) {
    auto item = ibus_property_new(
        (std::string("Scheme/") + (std::string(value) == "quanpin" ? "Quanpin" : std::string(value) == "shuangpin" ? "Shuangpin" : "Wubi")).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("直接选择中文输入方案"), TRUE, TRUE,
        !japanese_scheme && active_chinese_scheme == value
            ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(scheme_menu, item);
  }
  ibus_property_set_sub_props(scheme, scheme_menu);
  auto profile = ibus_property_new(
      "ShuangpinProfile", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("双拼方案"), "",
      ibus_text_new_from_static_string("选择双拼键位方案"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto profile_menu = ibus_prop_list_new();
  const auto configured_profile = s.shuangpin_profile_override.value_or(
      configured.at("preferences").value("shuangpin_profile", "xiaohe"));
  for (const auto &[value, label] : {std::pair{"xiaohe", "小鹤"},
                                     std::pair{"ziranma", "自然码"},
                                     std::pair{"shoudao", "搜狗"},
                                     std::pair{"microsoft", "微软"}}) {
    auto item = ibus_property_new(
        (std::string("ShuangpinProfile/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("切换双拼键位方案"), TRUE, TRUE,
        configured_profile == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(profile_menu, item);
  }
  ibus_property_set_sub_props(profile, profile_menu);
  if (registration) {
    auto properties = ibus_prop_list_new();
    ibus_prop_list_append(properties, toolbar);
    ibus_prop_list_append(properties, candidate_actions(engine));
    ibus_prop_list_append(properties, property);
    ibus_prop_list_append(properties, voice);
    ibus_prop_list_append(properties, cloud);
    ibus_prop_list_append(properties, punctuation);
    ibus_prop_list_append(properties, smart_punctuation);
    ibus_prop_list_append(properties, smart_repeat);
    ibus_prop_list_append(properties, paired);
    ibus_prop_list_append(properties, punctuation_lock);
    ibus_prop_list_append(properties, character_mode);
    ibus_prop_list_append(properties, traditional);
    ibus_prop_list_append(properties, english);
    ibus_prop_list_append(properties, english_mode);
    ibus_prop_list_append(properties, autocorrect_property);
    ibus_prop_list_append(properties, helpcode_property);
    ibus_prop_list_append(properties, helpcode_schema);
    ibus_prop_list_append(properties, emoji);
    ibus_prop_list_append(properties, kaomoji);
    ibus_prop_list_append(properties, clipboard);
    ibus_prop_list_append(properties, layout_property);
    ibus_prop_list_append(properties, page_size_property);
    ibus_prop_list_append(properties, frequency_property);
    ibus_prop_list_append(properties, number_row_property);
    ibus_prop_list_append(properties, nine_key_property);
    ibus_prop_list_append(properties, nine_key_spellings_property);
    ibus_prop_list_append(properties, local_modes_property);
    ibus_prop_list_append(properties, word_character_property);
    ibus_prop_list_append(properties, preedit_property);
    ibus_prop_list_append(properties, theme_property);
    ibus_prop_list_append(properties, skin_property);
    ibus_prop_list_append(properties, scheme);
    ibus_prop_list_append(properties, profile);
    ibus_engine_register_properties(engine, properties);
  } else {
    ibus_engine_update_property(engine, toolbar);
    ibus_engine_update_property(engine, candidate_actions(engine));
    ibus_engine_update_property(engine, property);
    ibus_engine_update_property(engine, voice);
    ibus_engine_update_property(engine, cloud);
    ibus_engine_update_property(engine, punctuation);
    ibus_engine_update_property(engine, smart_punctuation);
    ibus_engine_update_property(engine, smart_repeat);
    ibus_engine_update_property(engine, paired);
    ibus_engine_update_property(engine, punctuation_lock);
    ibus_engine_update_property(engine, character_mode);
    ibus_engine_update_property(engine, traditional);
    ibus_engine_update_property(engine, english);
    ibus_engine_update_property(engine, english_mode);
    ibus_engine_update_property(engine, autocorrect_property);
    ibus_engine_update_property(engine, helpcode_property);
    ibus_engine_update_property(engine, helpcode_schema);
    ibus_engine_update_property(engine, emoji);
    ibus_engine_update_property(engine, kaomoji);
    ibus_engine_update_property(engine, clipboard);
    ibus_engine_update_property(engine, layout_property);
    ibus_engine_update_property(engine, page_size_property);
    ibus_engine_update_property(engine, frequency_property);
    ibus_engine_update_property(engine, number_row_property);
    ibus_engine_update_property(engine, nine_key_property);
    ibus_engine_update_property(engine, nine_key_spellings_property);
    ibus_engine_update_property(engine, local_modes_property);
    ibus_engine_update_property(engine, word_character_property);
    ibus_engine_update_property(engine, preedit_property);
    ibus_engine_update_property(engine, theme_property);
    ibus_engine_update_property(engine, skin_property);
    ibus_engine_update_property(engine, scheme);
    ibus_engine_update_property(engine, profile);
  }
}
void clear(IBusEngine *engine) {
  ibus_engine_update_preedit_text_with_mode(
      engine, ibus_text_new_from_static_string(""), 0, FALSE,
      IBUS_ENGINE_PREEDIT_CLEAR);
  ibus_engine_hide_lookup_table(engine);
  ibus_engine_hide_auxiliary_text(engine);
}
void sync_global_input_mode(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.mode_scope_global || !global_input_enabled ||
      s.input_enabled == *global_input_enabled)
    return;
  s.invalidate_providers();
  if (!*global_input_enabled && s.session)
    apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
  s.input_enabled = *global_input_enabled;
  s.open();
  if (s.session)
    apply(engine, msime_client_focus(s.session, s.input_enabled));
  clear(engine);
  publish_mode(engine);
}
[[maybe_unused]] void publish_input_enabled(IBusEngine *engine, bool enabled) {
  auto property = ibus_property_new(
      "InputEnabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("输入启用"), "",
      ibus_text_new_from_static_string("启用或停用当前 Linux 输入会话"), TRUE,
      TRUE, enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
[[maybe_unused]] void publish_punctuation(IBusEngine *engine, bool enabled) {
  auto property = ibus_property_new(
      "ChinesePunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("启用中文标点转换"), TRUE, TRUE,
      enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
[[maybe_unused]] void publish_character_width(IBusEngine *engine, bool fullwidth) {
  auto property = ibus_property_new(
      "CharacterWidth", PROP_TYPE_TOGGLE, ibus_text_new_from_static_string("全角字符"), "",
      ibus_text_new_from_static_string("切换 ASCII 字符的全角/半角输出"), TRUE, TRUE,
      fullwidth ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
[[maybe_unused]] void publish_expressive(IBusEngine *engine, const State &s) {
  const auto preferences = configured.at("preferences").value("mixed_input", Json::object());
  const auto value = [&](const std::optional<bool> &override_value,
                         const char *key, bool fallback) {
    return override_value.value_or(preferences.value(key, fallback));
  };
  for (const auto &[name, label, key, fallback] : {
           std::tuple<const char *, const char *, const char *, bool>{
               "EnglishCandidates", "英文候选", "english", true},
           {"EmojiCandidates", "Emoji候选", "emoji", false},
           {"KaomojiCandidates", "颜文字候选", "kaomoji", false}}) {
    const auto &override_value = std::string(key) == "english"
                                     ? s.english_override
                                     : std::string(key) == "emoji"
                                           ? s.emoji_override
                                           : s.kaomoji_override;
    auto property = ibus_property_new(
        name, PROP_TYPE_TOGGLE, ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("在中文方案中补充表达候选"), TRUE, TRUE,
        value(override_value, key, fallback) ? PROP_STATE_CHECKED
                                              : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_engine_update_property(engine, property);
    }
}
void render(IBusEngine *engine, const Json &view) {
  ibus_engine_update_property(engine, candidate_actions(engine));
  // Engine caret offsets refer to ASCII editing_text, never the display
  // preedit.
  const auto style = state(engine).preedit_style;
  if (!state(engine).voice_preedit.empty()) {
    ibus_engine_update_preedit_text_with_mode(
        engine,
        ibus_text_new_from_string(state(engine).voice_preedit.c_str()),
        static_cast<guint>(state(engine).voice_preedit.size()), TRUE,
        IBUS_ENGINE_PREEDIT_CLEAR);
    ibus_engine_hide_lookup_table(engine);
    ibus_engine_hide_auxiliary_text(engine);
    return;
  }
  auto text = style == "pinyin" ? view.at("preedit").get<std::string>()
                                 : view.at("editing_text").get<std::string>();
  const auto caret = view.at("caret_position").get<size_t>();
  if (style == "raw" && (caret > text.size() ||
      std::any_of(text.begin(), text.end(),
                  [](unsigned char c) { return c < 0x20 || c > 0x7e; })))
    throw std::runtime_error("Invalid editing text");
  ibus_engine_update_preedit_text_with_mode(
      engine, ibus_text_new_from_string(text.c_str()),
      static_cast<guint>(style == "raw" ? caret : text.size()),
      style != "empty" && !text.empty(), IBUS_ENGINE_PREEDIT_CLEAR);
  const auto &candidates = view.at("candidates");
  if (candidates.empty()) {
    ibus_engine_hide_lookup_table(engine);
    ibus_engine_hide_auxiliary_text(engine);
    return;
  }
  auto paging = std::to_string(view.at("page").get<size_t>() + 1) + "/" +
                std::to_string(view.at("page_count").get<size_t>());
  if (state(engine).candidate_preedit_style == "pinyin") {
    const auto candidate_preedit = view.value("preedit", std::string{});
    if (!candidate_preedit.empty()) {
      paging += "  · ";
      paging += candidate_preedit;
    }
  }
  const auto mode = view.at("local_mode").get<std::string>();
  const std::pair<const char *, const char *> labels[] = {
      {"unicode", "U+"}, {"date_time", "日期时间"},
      {"quick_phrase", "短语"}, {"emoji", "Emoji"},
      {"kaomoji", "颜文字"}, {"super_jianpin", "简拼"},
      {"temporary_english", "EN"}, {"temporary_japanese", "日文"}};
  for (const auto &[name, label] : labels) {
    if (mode == name) {
      paging += "  · ";
      paging += label;
      break;
    }
  }
  ibus_engine_update_auxiliary_text(
      engine, ibus_text_new_from_string(paging.c_str()), TRUE);
  auto table = ibus_lookup_table_new(static_cast<guint>(candidates.size()), 0,
                                     TRUE, FALSE);
  ibus_lookup_table_set_orientation(table, state(engine).candidate_orientation);
  for (size_t index = 0; index < candidates.size(); ++index) {
    const auto &candidate = candidates.at(index);
    auto value = candidate.at("text").get<std::string>();
    if (state(engine).candidate_orientation == IBUS_ORIENTATION_VERTICAL &&
        candidate.contains("translation") && !candidate.at("translation").is_null()) {
      auto translation = candidate.at("translation").get<std::string>();
      // IBus lookup rows are plain text; preserve the candidate and expose
      // the optional gloss without allowing an oversized provider result to
      // destabilize the panel.
      if (!translation.empty() && translation.size() <= 4096 &&
          value.size() <= 4096)
        value += " · " + translation;
    }
    switch (candidate.value("source", 0)) {
    case 2: value += "  云"; break;
    case 3: value += "  AI"; break;
    default: break;
    }
    const auto fixed_position = candidate.value("fixed_position", 0);
    if (fixed_position >= 1 && fixed_position <= 5)
      value += "  固定" + std::to_string(fixed_position);
    const auto annotation = candidate.value("annotation", std::string{});
    if (!annotation.empty() && state(engine).show_helpcode_in_candidate_window) {
      value += "  ";
      value += annotation;
    }
    value = traditional_display(state(engine), view, std::move(value));
    auto text = ibus_text_new_from_string(value.c_str());
    if (state(engine).candidate_text_color)
      ibus_text_append_attribute(
          text, IBUS_ATTR_TYPE_FOREGROUND,
          *state(engine).candidate_text_color, 0, G_MAXUINT);
    if (state(engine).candidate_background_color)
      ibus_text_append_attribute(
          text, IBUS_ATTR_TYPE_BACKGROUND,
          *state(engine).candidate_background_color, 0, G_MAXUINT);
    ibus_lookup_table_append_candidate(table, text);
    auto label = std::to_string(index + 1);
    ibus_lookup_table_append_label(table,
                                   ibus_text_new_from_string(label.c_str()));
    if (candidate.at("highlighted").get<bool>())
      ibus_lookup_table_set_cursor_pos(table, static_cast<guint>(index));
  }
  ibus_engine_update_lookup_table(engine, table, TRUE);
}
bool apply(IBusEngine *engine, char *raw, PunctuationPairMode pair_mode) {
  auto result = response(raw);
  const auto &commit = result.at("commit");
  if (commit.is_string()) {
    auto text = commit.get<std::string>();
    auto &s = state(engine);
    text = traditional_display(
        s, result.value("commit_context", Json(nullptr)), std::move(text));
    normalize_punctuation_pair(text, pair_mode);
    if (s.smart_punctuation && s.paired_punctuation && text.size() == 1 &&
        smart_punctuation_pair(text.front())) {
      s.last_smart_punctuation = text.front();
      s.last_smart_punctuation_time = g_get_monotonic_time();
    } else if (text.size() != 1 || !smart_punctuation_pair(text.front())) {
      s.last_smart_punctuation = 0;
      s.last_smart_punctuation_time = 0;
    }
    if (state(engine).fullwidth)
      text = fullwidth_text(text);
    if (!text.empty())
      ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
  }
  state(engine).view = result.at("view");
  render(engine, state(engine).view);
  online_schedule(engine);
  translation_schedule(engine);
  return result.at("handled").get<bool>();
}
template <class F> void guarded(IBusEngine *engine, const char *operation, F action) noexcept {
  try {
    action();
  } catch (...) {
    // Never log the raw error or response: either can include input or paths.
    g_warning("MSIME preview host operation failed: %s", operation);
    state(engine).close();
    clear(engine);
    publish_mode(engine);
  }
}
struct VoiceResult {
  IBusEngine *engine;
  std::shared_ptr<std::atomic_bool> alive;
  uint64_t generation;
  std::string text;
  bool final = true;
};
struct VoiceStreamContext {
  MsimeVoiceWorker::Progress progress;
};
extern "C" void voice_provider_stream_update(const uint8_t *text,
                                               size_t length, bool final,
                                               void *context) {
  auto *stream = static_cast<VoiceStreamContext *>(context);
  if (!stream || !stream->progress || !text || length == 0 || length > 4096)
    return;
  stream->progress(msime_voice_bound_result(
                       std::string(reinterpret_cast<const char *>(text), length)),
                   final);
}
Json voice_provider_options(const Json &preferences) {
  const auto voice = preferences.value("voice_input", Json::object());
  Json options = Json::object();
  constexpr const char *boolean_keys[] = {
      "sound_enabled", "start_sound", "end_sound", "mute_system_audio",
      "polish_enabled", "polish_text", "doubao_enable_itn",
      "doubao_enable_punc", "doubao_enable_ddc", "stream_inline_preedit"};
  for (const auto *key : boolean_keys) {
    if (voice.contains(key) && voice.at(key).is_boolean())
      options[key] = voice.at(key);
  }
  constexpr const char *string_keys[] = {
      "commit_mode", "asr_provider", "asr_model", "asr_resource_id",
      "polish_provider", "polish_model", "doubao_boosting_table_id",
      "polish_prompt_id", "polish_prompt", "polish_prompt_custom_1",
      "polish_prompt_custom_2", "polish_prompt_custom_3"};
  for (const auto *key : string_keys) {
    if (!voice.contains(key) || !voice.at(key).is_string())
      continue;
    auto value = voice.at(key).get<std::string>();
    if (value.size() > 512)
      value.resize(512);
    options[key] = std::move(value);
  }
  return options;
}
void voice_cancel(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.voice_active && !s.voice_provider_socket.empty())
    msime_client_string_free(msime_client_voice_provider_cancel(
        reinterpret_cast<const uint8_t *>(s.voice_provider_socket.data()),
        s.voice_provider_socket.size(), s.voice_generation));
  if (s.voice_active && s.session)
    msime_client_string_free(msime_client_voice_cancel(s.session));
  s.voice_active = false;
  s.voice_generation = 0;
  s.voice_preedit.clear();
  s.voice_space_consumed = false;
  s.voice_space_locked = false;
  s.voice_worker.cancel_async();
  if (s.session)
    render(engine, s.view);
  publish_mode(engine);
}
void voice_stop(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.voice_active || s.voice_provider_socket.empty())
    return;
  std::unique_ptr<char, decltype(&msime_client_string_free)> owned(
      msime_client_voice_provider_stop(
          reinterpret_cast<const uint8_t *>(s.voice_provider_socket.data()),
          s.voice_provider_socket.size(), s.voice_generation),
      msime_client_string_free);
  bool stopped = false;
  if (owned) {
    try {
      const auto result = Json::parse(owned.get());
      stopped = result.at("ok").get<bool>() && result.at("value").get<bool>();
    } catch (...) {
      stopped = false;
    }
  }
  if (!stopped)
    voice_cancel(engine);
  else {
    s.voice_space_consumed = false;
    s.voice_space_locked = false;
    publish_mode(engine);
  }
}
void voice_start(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.voice_enabled || s.voice_provider_socket.empty() || !s.session ||
      !s.focused || s.blocked || !s.input_enabled || s.voice_active)
    return;
  const auto started = response(msime_client_voice_start(s.session));
  const auto generation = started.get<uint64_t>();
  s.voice_active = true;
  s.voice_generation = generation;
  s.voice_space_consumed = false;
  s.voice_space_locked = false;
  const auto socket = s.voice_provider_socket;
  const auto language = s.voice_language;
  const auto provider_options = voice_provider_options(
      configured.value("preferences", Json::object()));
  const bool stream_inline_preedit =
      provider_options.value("stream_inline_preedit", false);
  const auto alive = s.alive;
  s.voice_worker.run_stream(
      [socket, language, generation,
       provider_options](const std::atomic_bool &cancelled,
                         const MsimeVoiceWorker::Progress &progress) {
        if (cancelled.load())
          return std::string{};
        const auto query = Json{{"language", language},
                                {"generation", generation},
                                {"options", provider_options}}
                               .dump();
        VoiceStreamContext stream{progress};
        auto *raw = msime_client_voice_provider_stream(
            reinterpret_cast<const uint8_t *>(query.data()), query.size(),
            reinterpret_cast<const uint8_t *>(socket.data()), socket.size(),
            voice_provider_stream_update, &stream);
        std::unique_ptr<char, decltype(&msime_client_string_free)> owned(
            raw, msime_client_string_free);
        if (cancelled.load() || !raw)
          return std::string{};
        try {
          const auto document = Json::parse(raw);
          if (!document.value("ok", false))
            return std::string{};
          const auto value = document.at("value");
          if (!value.is_object())
            return std::string{};
          return msime_voice_bound_result(value.value("text", std::string{}));
        } catch (...) {
          return std::string{};
        }
      },
      [engine, alive, generation,
       stream_inline_preedit](std::string text, bool final) {
        if (!stream_inline_preedit || final || text.empty())
          return;
        auto *result = new VoiceResult{engine, alive, generation,
                                       std::move(text), false};
        g_main_context_invoke(
            nullptr,
            +[](gpointer data) -> gboolean {
              std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
              if (!result->alive->load())
                return G_SOURCE_REMOVE;
              auto &s = state(result->engine);
              if (!s.voice_active || s.voice_generation != result->generation ||
                  !s.session || !s.focused || s.blocked || !s.input_enabled)
                return G_SOURCE_REMOVE;
              s.voice_preedit = msime_voice_bound_result(std::move(result->text));
              ibus_engine_update_preedit_text_with_mode(
                  result->engine,
                  ibus_text_new_from_string(s.voice_preedit.c_str()),
                  static_cast<guint>(g_utf8_strlen(s.voice_preedit.c_str(), -1)),
                  TRUE, IBUS_ENGINE_PREEDIT_CLEAR);
              return G_SOURCE_REMOVE;
            },
            result);
      },
      [engine, alive, generation](std::string text) {
        auto *result = new VoiceResult{engine, alive, generation, std::move(text)};
        g_main_context_invoke(
            nullptr,
            +[](gpointer data) -> gboolean {
              std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
              if (!result->alive->load())
                return G_SOURCE_REMOVE;
              auto &s = state(result->engine);
              if (!s.voice_active || s.voice_generation != result->generation ||
                  !s.session || !s.focused || s.blocked || !s.input_enabled) {
                return G_SOURCE_REMOVE;
              }
              try {
                if (result->text.empty()) {
                  msime_client_string_free(msime_client_voice_cancel(s.session));
                  s.voice_active = false;
                  s.voice_generation = 0;
                  s.voice_preedit.clear();
                  s.voice_hotkey_consumed_key = 0;
                  s.voice_space_consumed = false;
                  s.voice_space_locked = false;
                  render(result->engine, s.view);
                  publish_mode(result->engine);
                  return G_SOURCE_REMOVE;
                }
                auto applied = response(msime_client_voice_apply(
                    s.session, result->generation,
                    reinterpret_cast<const uint8_t *>(result->text.data()),
                    result->text.size()));
                s.voice_active = false;
                s.voice_generation = 0;
                s.voice_preedit.clear();
                s.voice_hotkey_consumed_key = 0;
                s.voice_space_consumed = false;
                s.voice_space_locked = false;
                if (applied.is_string()) {
                  auto text = traditional_display(
                      s, Json{{"scheme", s.view.value("scheme", 0)},
                              {"local_mode", "none"}},
                      applied.get<std::string>());
                  if (s.fullwidth)
                    text = fullwidth_text(std::move(text));
                  ibus_engine_commit_text(
                      result->engine,
                      ibus_text_new_from_string(text.c_str()));
                }
                render(result->engine, s.view);
                publish_mode(result->engine);
              } catch (...) {
                s.voice_active = false;
                s.voice_generation = 0;
                s.voice_preedit.clear();
                s.voice_hotkey_consumed_key = 0;
                s.voice_space_consumed = false;
                s.voice_space_locked = false;
                msime_client_string_free(msime_client_voice_cancel(s.session));
                publish_mode(result->engine);
              }
              return G_SOURCE_REMOVE;
            },
            result);
      });
  publish_mode(engine);
}
bool voice_hotkey(const State &s, guint key, guint modifiers) {
  if (key == IBUS_F9 && modifiers == IBUS_CONTROL_MASK)
    return s.voice_hotkey_ctrl_f9;
  if (key == IBUS_Alt_R && modifiers == (IBUS_MOD1_MASK | IBUS_CONTROL_MASK))
    return s.voice_hotkey_rctrl_ralt;
  if (key == IBUS_Alt_R && modifiers == IBUS_MOD1_MASK)
    return s.voice_hotkey_ralt;
  if ((key == IBUS_Super_L || key == IBUS_Super_R) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_MOD4_MASK))
    return s.voice_hotkey_ctrl_win;
  return false;
}
bool voice_hold_hotkey(const State &s, guint key, guint modifiers) {
  if (key == IBUS_F9)
    return false;
  return voice_hotkey(s, key, modifiers);
}
void set_surrounding(IBusEngine *engine, IBusText *text, guint cursor, guint anchor) {
  // Keep platform context available without feeding it into Engine composition.
  auto &s = state(engine);
  s.surrounding_text = text && ibus_text_get_text(text) ? ibus_text_get_text(text) : "";
  const auto length = static_cast<guint>(s.surrounding_text.size());
  auto utf8_boundary = [&](guint offset) {
    auto value = std::min(offset, length);
    // IBus offsets are bytes; never split a UTF-8 sequence when forwarding
    // surrounding text to the engine.
    while (value > 0 && value < length &&
           (static_cast<unsigned char>(s.surrounding_text[value]) & 0xc0) == 0x80)
      --value;
    return value;
  };
  s.surrounding_cursor = utf8_boundary(cursor);
  s.surrounding_anchor = utf8_boundary(anchor);
}
void focus_in(IBusEngine *engine) {
  guarded(engine, "focus_in", [&] {
    auto &s = state(engine);
    s.focused = true;
    s.open();
    sync_global_input_mode(engine);
    if (s.session)
      apply(engine, msime_client_focus(s.session, s.input_enabled));
    if (!s.properties_registered &&
        g_getenv("MSIME_DISABLE_IBUS_PROPERTIES") == nullptr) {
      register_properties(engine);
      s.properties_registered = true;
    }
  });
}
void focus_out(IBusEngine *engine) {
  guarded(engine, "focus_out", [&] {
    auto &s = state(engine);
    voice_cancel(engine);
    s.voice_hotkey_consumed_key = 0;
    s.focused = false;
    s.invalidate_providers();
    s.surrounding_text.clear();
    s.surrounding_cursor = 0;
    s.surrounding_anchor = 0;
    s.last_smart_punctuation = 0;
    s.last_smart_punctuation_time = 0;
    s.smart_punctuation_rejected = 0;
    if (s.session)
      apply(engine, msime_client_focus(s.session, false));
    clear(engine);
    publish_mode(engine);
  });
}
void property_activate(IBusEngine *engine, const gchar *name, guint value) {
  const std::string candidate_name = name ? name : "";
  if (candidate_name.rfind("CandidatePin", 0) == 0 ||
      candidate_name.rfind("CandidateRemove", 0) == 0 ||
      candidate_name.rfind("CandidateFix", 0) == 0 ||
      candidate_name.rfind("CandidateClear", 0) == 0) {
    guarded(engine, "candidate_property", [&] {
      auto &s = state(engine);
      if (!s.session || !s.focused || s.blocked || !s.input_enabled)
        return;
      for (const auto &candidate : s.view.at("candidates")) {
        const auto &id = candidate.at("id");
        const bool pin = candidate_name == candidate_action_name("CandidatePin", id);
        const bool remove = candidate_name == candidate_action_name("CandidateRemove", id);
        const bool clear = candidate_name == candidate_action_name("CandidateClear", id);
        uint8_t position = 0;
        for (uint8_t slot = 1; slot <= 5; ++slot) {
          if (candidate_name == candidate_action_name(
                  (std::string("CandidateFix") + std::to_string(slot)).c_str(), id)) {
            position = slot;
            break;
          }
        }
        if (!pin && !remove && !clear && position == 0)
          continue;
        if (id.at("session").get<uint64_t>() != s.session)
          return;
        const auto source = candidate.value("source", 0);
        if (s.view.value("scheme", 255) == 3 ||
            (source != 0 && source != 1 && source != 4))
          return;
        const auto generation = id.at("generation").get<uint64_t>();
        const auto index = id.at("index").get<size_t>();
        if (pin)
          apply(engine, msime_client_pin_candidate(s.session, generation, index));
        else if (remove)
          apply(engine, msime_client_remove_candidate(s.session, generation, index));
        else if (clear)
          apply(engine, msime_client_clear_candidate_position(s.session, generation, index));
        else
          apply(engine, msime_client_fix_candidate_position(s.session, generation, index, position));
        return;
      }
    });
    return;
  }
  if (candidate_name.rfind("NineKeySpelling/", 0) == 0) {
    guarded(engine, "nine_key_spelling", [&] {
      auto &s = state(engine);
      if (!s.session || !s.focused || s.blocked || !s.input_enabled ||
          !s.view.value("nine_key", false))
        return;
      const auto spellings = s.view.value("nine_key_spellings", Json::array());
      if (!spellings.is_array())
        return;
      const auto generation = s.view.value("generation", uint64_t{0});
      for (size_t index = 0; index < spellings.size(); ++index) {
        if (!spellings.at(index).is_string() ||
            candidate_name != nine_key_spelling_action_name(s.session, generation, index))
          continue;
        apply(engine, msime_client_choose_nine_key_spelling(
                         s.session, generation, index));
        return;
      }
    });
    return;
  }
  auto &s = state(engine);
  const std::string property_name = name ? name : "";
  if (property_name.rfind("Toolbar/", 0) == 0) {
    if (property_name == "Toolbar/Emoji") {
      launch_desktop_panel("emoji");
      return;
    }
    if (property_name == "Toolbar/ScreenKeyboard") {
      launch_desktop_panel("keyboard");
      return;
    }
    if (property_name == "Toolbar/Settings") {
      launch_desktop_panel("settings");
      return;
    }
    const char *target =
        property_name == "Toolbar/InputMode" ? "InputMode"
        : property_name == "Toolbar/EnglishMode" ? "EnglishMode"
        : property_name == "Toolbar/Fullwidth" ? "CharacterMode"
        : property_name == "Toolbar/Punctuation" ? "Punctuation"
        : property_name == "Toolbar/CharacterSet" ? "TraditionalOutput"
        : nullptr;
    if (target && (value == PROP_STATE_CHECKED || value == PROP_STATE_UNCHECKED))
      property_activate(engine, target, value);
    return;
  }
  const bool clipboard_item = property_name.rfind("ClipboardHistory/", 0) == 0 &&
                               property_name != "ClipboardHistory/Latest" &&
                               property_name != "ClipboardHistory/Clear" &&
                               property_name.rfind("ClipboardHistory/Remove/", 0) != 0;
  const bool clipboard_remove = property_name.rfind("ClipboardHistory/Remove/", 0) == 0;
  if (!name ||
       (!(clipboard_item || clipboard_remove) && property_name != "ClipboardHistory/Clear" &&
       std::string(name) != "InputMode" &&
       std::string(name) != "VoiceInput" &&
       std::string(name) != "CloudCandidates" &&
       std::string(name) != "Punctuation" &&
       std::string(name) != "SmartPunctuation" &&
       std::string(name) != "SmartPunctuationRepeat" &&
       std::string(name) != "PairedPunctuation" &&
       std::string(name) != "PunctuationLock/follow" &&
       std::string(name) != "PunctuationLock/chinese" &&
       std::string(name) != "PunctuationLock/english" &&
       std::string(name) != "CharacterMode" &&
       std::string(name) != "TraditionalOutput" &&
       std::string(name) != "EnglishCandidates" &&
       std::string(name) != "EnglishMode" &&
       std::string(name) != "Autocorrect" &&
       std::string(name) != "Helpcode" &&
       property_name.rfind("HelpcodeSchema/", 0) != 0 &&
       std::string(name) != "EmojiCandidates" &&
       std::string(name) != "KaomojiCandidates" &&
       std::string(name) != "CandidateLayout/Vertical" &&
       std::string(name) != "CandidateLayout/Horizontal" &&
       property_name.rfind("CandidatePageSize/", 0) != 0 &&
       property_name.rfind("FrequencyMode/", 0) != 0 &&
       std::string(name) != "NumberRowSelection" &&
       std::string(name) != "NineKey" &&
       property_name.rfind("LocalModes/", 0) != 0 &&
       std::string(name) != "WordCharacter" &&
       std::string(name) != "PreeditStyle/raw" &&
       std::string(name) != "PreeditStyle/pinyin" &&
       std::string(name) != "PreeditStyle/empty" &&
       std::string(name) != "CandidateTheme/follow" &&
       std::string(name) != "CandidateTheme/light" &&
       std::string(name) != "CandidateTheme/dark" &&
       std::string(name) != "Scheme/Chinese" &&
       std::string(name) != "Scheme/Japanese" &&
       property_name != "Scheme/Quanpin" && property_name != "Scheme/Shuangpin" &&
       property_name != "Scheme/Wubi" &&
       property_name.rfind("ShuangpinProfile/", 0) != 0) ||
      !s.focused || s.blocked ||
      (value != PROP_STATE_CHECKED && value != PROP_STATE_UNCHECKED))
    return;
  guarded(engine, "property_activate", [&] {
    if (property_name == "VoiceInput") {
      if (!s.voice_enabled || s.voice_provider_socket.empty() || !s.session ||
          !s.input_enabled)
        return;
      if (value == PROP_STATE_CHECKED)
        voice_start(engine);
      else if (s.voice_active)
        voice_cancel(engine);
      return;
    }
    if (property_name == "CloudCandidates") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (enabled == s.cloud_candidates)
        return;
      s.cloud_candidates_override = enabled;
      s.cloud_candidates = enabled;
      s.invalidate_providers();
      publish_mode(engine);
      return;
    }
    if (property_name == "NumberRowSelection") {
      if (s.view.value("nine_key", false))
        return;
      s.number_row_selection = value == PROP_STATE_CHECKED;
      s.number_row_override = s.number_row_selection;
      publish_mode(engine);
      return;
    }
    if (property_name == "NineKey") {
      const bool enabled = value == PROP_STATE_CHECKED;
      const auto active_scheme = s.scheme_override.value_or(
          configured.at("preferences").value("scheme", "quanpin"));
      if (active_scheme != "quanpin" ||
          s.view.value("nine_key", false) == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.nine_key_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (property_name.rfind("LocalModes/", 0) == 0) {
      const auto key = property_name.substr(std::string("LocalModes/").size());
      const auto allowed = [](const std::string &value) {
        return value == "unicode" || value == "date_time" ||
               value == "quick_phrase" || value == "emoji" ||
               value == "kaomoji" || value == "super_jianpin" ||
               value == "temporary_english" || value == "temporary_japanese";
      };
      if (!allowed(key))
        return;
      const auto configured_modes = configured.at("preferences").value(
          "local_modes", Json::object());
      const bool current = s.local_mode_overrides.contains(key)
                               ? s.local_mode_overrides.at(key).get<bool>()
                               : configured_modes.value(key, true);
      const bool enabled = value == PROP_STATE_CHECKED;
      if (current == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.local_mode_overrides[key] = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (property_name == "WordCharacter") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.word_character_override.value_or(s.word_character.enabled) == enabled)
        return;
      s.word_character_override = enabled;
      s.word_character.enabled = enabled;
      publish_mode(engine);
      return;
    }
    if (property_name.rfind("HelpcodeSchema/", 0) == 0) {
      const auto selected = property_name.substr(std::string("HelpcodeSchema/").size());
      if (selected != "lantian" && selected != "ziranma" && selected != "shouyou2_0" &&
          selected != "shouyouplus" && selected != "xiaohe")
        return;
      const auto active_scheme = s.scheme_override.value_or(
          configured.at("preferences").value("scheme", "quanpin"));
      if (active_scheme != "quanpin" && active_scheme != "shuangpin")
        return;
      if (s.helpcode_schema_override.value_or(
              configured.at("preferences").value(active_scheme + "_helpcode", Json::object())
                  .value("schema", "ziranma")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.helpcode_schema_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (property_name.rfind("FrequencyMode/", 0) == 0) {
      const auto selected = property_name.substr(std::string("FrequencyMode/").size());
      if (selected != "disabled" && selected != "pin" && selected != "halve" &&
          selected != "linear" && selected != "promote")
        return;
      if (s.frequency_mode_override.value_or(
              configured.at("preferences").value("frequency", Json::object())
                  .value("mode", "promote")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.frequency_mode_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (property_name.rfind("CandidatePageSize/", 0) == 0) {
      try {
        const auto selected = std::stoul(property_name.substr(18));
        if (selected < 1 || selected > 9 || !s.session)
          return;
        s.candidate_page_size_override = static_cast<uint8_t>(selected);
        apply(engine, msime_client_set_candidate_page_size(
                         s.session, static_cast<uint8_t>(selected)));
        publish_mode(engine);
      } catch (...) {
      }
      return;
    }
    if (property_name.rfind("ShuangpinProfile/", 0) == 0) {
      const auto selected = property_name.substr(std::string("ShuangpinProfile/").size());
      if (selected != "xiaohe" && selected != "ziranma" && selected != "shoudao" &&
          selected != "microsoft")
        return;
      if (s.shuangpin_profile_override.value_or(
              configured.at("preferences").value("shuangpin_profile", "xiaohe")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.shuangpin_profile_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (clipboard_remove) {
      try {
        const auto index = std::stoul(property_name.substr(24));
        if (clipboard_remove_index(s.clipboard_history_path, index)) {
          s.clipboard_items_cache.clear();
          s.clipboard_loaded = false;
          ++s.clipboard_generation;
          publish_mode(engine);
        }
      } catch (...) {
      }
      return;
    }
    if (property_name == "ClipboardHistory/Clear") {
      if (s.clipboard_history_path.empty())
        return;
      std::error_code error;
      std::filesystem::remove(s.clipboard_history_path, error);
      s.clipboard_items_cache.clear();
      s.clipboard_loaded = false;
      ++s.clipboard_generation;
      publish_mode(engine);
      return;
    }
    if (clipboard_item) {
      try {
        const auto index = std::stoul(property_name.substr(17));
        const auto items = clipboard_items(s.clipboard_history_path);
        if (index < items.size())
          ibus_engine_commit_text(engine, ibus_text_new_from_string(items[index].c_str()));
      } catch (...) {}
      return;
    }
    if (property_name == "PairedPunctuation") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.session)
        apply(engine, msime_client_set_paired_punctuation(s.session, enabled));
      s.paired_punctuation_override = enabled;
      s.paired_punctuation = enabled;
      s.last_smart_punctuation = 0;
      s.smart_punctuation_rejected = 0;
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuation") {
      s.smart_punctuation = value == PROP_STATE_CHECKED;
      s.smart_punctuation_override = s.smart_punctuation;
      if (!s.smart_punctuation) {
        s.last_smart_punctuation = 0;
        s.smart_punctuation_rejected = 0;
      }
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuationRepeat") {
      s.smart_punctuation_repeat = value == PROP_STATE_CHECKED;
      s.smart_repeat_override = s.smart_punctuation_repeat;
      if (!s.smart_punctuation_repeat) {
        s.last_smart_punctuation = 0;
        s.smart_punctuation_rejected = 0;
      }
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "CharacterMode") {
      s.fullwidth = value == PROP_STATE_CHECKED;
      if (s.session)
        apply(engine, msime_client_set_character_width(s.session, s.fullwidth));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "TraditionalOutput") {
      if (s.scheme_override.value_or(
              configured.at("preferences").value("scheme", "quanpin")) ==
          "japanese")
        return;
      s.traditional_output = value == PROP_STATE_CHECKED;
      s.traditional_output_override = s.traditional_output;
      render(engine, s.view);
      publish_mode(engine);
      return;
    }
    if (std::string(name).rfind("CandidateTheme/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("CandidateTheme/").size());
      if (s.theme_override.value_or(
              configured.at("preferences").value("candidate_theme", "follow")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.theme_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name).rfind("CandidateSkin/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("CandidateSkin/").size());
      if (s.skin_override.value_or(
              configured.at("preferences").value("candidate_skin", "fluent")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.skin_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name).rfind("PreeditStyle/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("PreeditStyle/").size());
      if (s.preedit_override.value_or(
              configured.at("preferences").value("tsf_preedit_style", "raw")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.preedit_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "CandidateLayout/Vertical" ||
        std::string(name) == "CandidateLayout/Horizontal") {
      const auto selected = std::string(name) == "CandidateLayout/Horizontal"
                                ? "horizontal" : "vertical";
      if (s.layout_override.value_or(
              configured.at("preferences").value("candidate_layout", "vertical")) == selected)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.layout_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "EmojiCandidates" ||
        std::string(name) == "KaomojiCandidates") {
      const bool enabled = value == PROP_STATE_CHECKED;
      auto &setting_override = std::string(name) == "EmojiCandidates"
                           ? s.emoji_override : s.kaomoji_override;
      const auto key = std::string(name) == "EmojiCandidates" ? "emoji" : "kaomoji";
      if (setting_override.value_or(configured.at("preferences").at("mixed_input").value(key, false)) == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      setting_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "EnglishCandidates") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.english_override.value_or(
              configured.at("preferences").at("mixed_input").value("english", false)) == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.english_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "EnglishMode") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (!s.input_enabled || !s.session || s.english_mode == enabled)
        return;
      s.view = response(msime_client_set_english_mode(s.session, enabled));
      s.english_mode = enabled;
      s.dedicated_english_override = enabled;
      render(engine, s.view);
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "Autocorrect") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.autocorrect_override.value_or(
              configured.at("preferences").value("autocorrect", true)) == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.autocorrect_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "Helpcode") {
      const bool enabled = value == PROP_STATE_CHECKED;
      const auto active_scheme = s.scheme_override.value_or(
          configured.at("preferences").value("scheme", "quanpin"));
      if (active_scheme != "quanpin" && active_scheme != "shuangpin")
        return;
      const bool current = s.helpcode_override.value_or(
          configured.at("preferences").value(active_scheme + "_helpcode", Json::object())
              .value("enabled", true));
      if (current == enabled)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.helpcode_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    if (std::string(name).rfind("Scheme/", 0) == 0) {
      const bool japanese = std::string(name) == "Scheme/Japanese";
      const bool explicit_chinese = property_name == "Scheme/Quanpin" ||
                                    property_name == "Scheme/Shuangpin" ||
                                    property_name == "Scheme/Wubi";
      if (!explicit_chinese &&
          (s.scheme_override && *s.scheme_override == "japanese") == japanese)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      if (japanese) {
        s.scheme_override = "japanese";
      } else {
        auto chinese = property_name == "Scheme/Quanpin"
                           ? std::string("quanpin")
                           : property_name == "Scheme/Shuangpin"
                                 ? std::string("shuangpin")
                                 : property_name == "Scheme/Wubi"
                                       ? std::string("wubi")
                                       : configured.at("preferences").value(
                                             "last_chinese_scheme", std::string("quanpin"));
        if (chinese != "quanpin" && chinese != "shuangpin" && chinese != "wubi")
          chinese = "quanpin";
        s.scheme_override = chinese;
      }
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    const bool enabled = value == PROP_STATE_CHECKED;
    if (std::string(name).rfind("PunctuationLock/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("PunctuationLock/").size());
      if (s.session)
        apply(engine, msime_client_set_punctuation_lock(
            s.session, selected == "chinese" ? 1 : selected == "english" ? 2 : 0));
      s.punctuation_lock_override = selected;
      s.punctuation_lock = selected;
      {
        const bool chinese = selected == "follow"
                                  ? s.punctuation_override.value_or(configured.at("preferences").value("chinese_punctuation", true))
                                  : selected == "chinese";
        if (s.session) {
          s.view = response(msime_client_set_chinese_punctuation(s.session, chinese));
          render(engine, s.view);
        }
        s.chinese_punctuation = chinese;
      }
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "Punctuation") {
      if (!s.input_enabled || !s.session)
        return;
      s.view =
          response(msime_client_set_chinese_punctuation(s.session, enabled));
      s.chinese_punctuation = enabled;
      s.punctuation_override = enabled;
      publish_mode(engine);
      return;
    }
    if (enabled != s.input_enabled) {
      s.invalidate_providers();
      if (!enabled && s.session)
        apply(engine,
              msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      if (s.mode_scope_global)
        global_input_enabled = enabled;
      s.input_enabled = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, enabled));
      clear(engine);
    }
    publish_mode(engine);
  });
}
void reset(IBusEngine *engine) {
  guarded(engine, "reset", [&] {
    if (state(engine).voice_active)
      voice_cancel(engine);
    state(engine).voice_hotkey_consumed_key = 0;
    state(engine).last_smart_punctuation = 0;
    state(engine).last_smart_punctuation_time = 0;
    state(engine).smart_punctuation_rejected = 0;
    if (state(engine).session)
      apply(engine, msime_client_command(state(engine).session, MSIME_CANCEL));
    clear(engine);
  });
}
void content_type(IBusEngine *engine, guint purpose, guint hints) {
  guarded(engine, "content_type", [&] {
    auto &s = state(engine);
    bool blocked = purpose == IBUS_INPUT_PURPOSE_PASSWORD ||
                   purpose == IBUS_INPUT_PURPOSE_PIN ||
                   purpose == IBUS_INPUT_PURPOSE_NUMBER ||
                   purpose == IBUS_INPUT_PURPOSE_DIGITS ||
                   purpose == IBUS_INPUT_PURPOSE_PHONE;
    bool private_input =
        (hints & (IBUS_INPUT_HINT_PRIVATE | IBUS_INPUT_HINT_NO_SPELLCHECK)) !=
        0;
    if (blocked == s.blocked && private_input == s.private_input)
      return;
    s.close();
    clear(engine);
    s.blocked = blocked;
    s.private_input = private_input;
    s.open();
    if (s.session)
      apply(engine, msime_client_focus(s.session, true));
    publish_mode(engine);
  });
}
bool modifier(guint key) {
  return (key >= IBUS_Shift_L && key <= IBUS_Hyper_R) || key == IBUS_Num_Lock ||
         key == IBUS_Scroll_Lock || key == IBUS_Mode_switch ||
         key == IBUS_ISO_Level3_Shift || key == IBUS_ISO_Level5_Shift;
}
std::optional<size_t> candidate_digit_slot(guint key, guint keycode,
                                           guint flags, const Json &view) {
  if (!view.is_object() ||
      view.value("local_mode", std::string("none")) == "unknown")
    return std::nullopt;
  const auto modifiers = flags &
      (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK |
       IBUS_SUPER_MASK | IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  const bool unicode = view.value("local_mode", std::string("none")) == "unicode";
  const bool shifted = (modifiers & IBUS_SHIFT_MASK) != 0;
  // Windows uses Shift+the physical number row for Unicode candidates, while
  // ordinary modes use the unmodified row. IBus exposes the shifted symbols
  // as key values, so map those symbols back to their physical slots.
  if (modifiers != (unicode ? IBUS_SHIFT_MASK : 0))
    return std::nullopt;
  if (!unicode) {
    // IBus keycode is the XKB hardware code on both X11 and Wayland. The
    // standard number row is 10..19 (1..9,0); using it preserves physical-key
    // selection when the active layout produces symbols such as '&' or 'é'.
    if (keycode >= 10 && keycode <= 19)
      return keycode == 19 ? 9 : static_cast<size_t>(keycode - 10);
    if (key >= IBUS_1 && key <= IBUS_9)
      return static_cast<size_t>(key - IBUS_1);
    if (key == IBUS_0)
      return 9;
    if (key >= IBUS_KP_1 && key <= IBUS_KP_9)
      return static_cast<size_t>(key - IBUS_KP_1);
    if (key == IBUS_KP_0)
      return 9;
    return std::nullopt;
  }
  if (!shifted)
    return std::nullopt;
  if (keycode >= 10 && keycode <= 19)
    return keycode == 19 ? 9 : static_cast<size_t>(keycode - 10);
  switch (key) {
  case '!': return 0;
  case '@': return 1;
  case '#': return 2;
  case '$': return 3;
  case '%': return 4;
  case '^': return 5;
  case '&': return 6;
  case '*': return 7;
  case '(': return 8;
  case ')': return 9;
  // Some X11 layouts keep keypad keysyms unchanged with Shift.
  case IBUS_KP_1: return 0;
  case IBUS_KP_2: return 1;
  case IBUS_KP_3: return 2;
  case IBUS_KP_4: return 3;
  case IBUS_KP_5: return 4;
  case IBUS_KP_6: return 5;
  case IBUS_KP_7: return 6;
  case IBUS_KP_8: return 7;
  case IBUS_KP_9: return 8;
  case IBUS_KP_0: return 9;
  default: return std::nullopt;
  }
}
std::optional<char> keypad_punctuation(guint key) {
  switch (key) {
  case IBUS_KP_Decimal:
    return '.';
  case IBUS_KP_Separator:
    return ',';
  case IBUS_KP_Subtract:
    return '-';
  case IBUS_KP_Add:
    return '+';
  case IBUS_KP_Divide:
    return '/';
  case IBUS_KP_Multiply:
    return '*';
#ifdef IBUS_KP_Equal
  case IBUS_KP_Equal:
    return '=';
#endif
  default:
    return std::nullopt;
  }
}
bool microsoft_shuangpin_ing_key(const Json &view, guint key, guint modifiers) {
  if (key != IBUS_semicolon || modifiers != 0 ||
      !view.value("microsoft_shuangpin", false))
    return false;
  const auto editing_text = view.value("editing_text", std::string{});
  const auto caret = std::min<std::size_t>(
      view.value("caret_position", editing_text.size()), editing_text.size());
  const auto separator = caret == 0
                             ? std::string::npos
                             : editing_text.rfind('\'', caret - 1);
  const auto chunk_start = separator == std::string::npos ? 0 : separator + 1;
  return (caret - chunk_start) % 2 == 1;
}
bool unicode_plus_key(const Json &view, guint key, guint modifiers) {
  return key == '+' && modifiers == IBUS_SHIFT_MASK &&
         view.value("local_mode", std::string("none")) == "unicode" &&
         view.value("editing_text", std::string{}) == "U";
}
void toggle_input_mode(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.voice_active)
    voice_cancel(engine);
  s.invalidate_providers();
  if (!s.input_enabled && s.session)
    apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
  s.input_enabled = !s.input_enabled;
  if (s.mode_scope_global)
    global_input_enabled = s.input_enabled;
  s.open();
  if (s.session)
    apply(engine, msime_client_focus(s.session, s.input_enabled));
  clear(engine);
  publish_mode(engine);
}
gboolean process_key(IBusEngine *engine, guint key, guint keycode, guint flags) {
  auto &s = state(engine);
  const bool shift_key = key == IBUS_Shift_L || key == IBUS_Shift_R;
  const bool ctrl_key = key == IBUS_Control_L || key == IBUS_Control_R;
  const bool release = (flags & IBUS_RELEASE_MASK) != 0;
  const guint chord_modifiers = flags &
      (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
       IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  if (shift_key && (flags & IBUS_RELEASE_MASK)) {
    if (!s.pure_shift_candidate || chord_modifiers) {
      s.pure_shift_candidate = false;
      return FALSE;
    }
    s.pure_shift_candidate = false;
    if (!s.focused || s.blocked)
      return FALSE;
    if (!s.view.is_null() && !s.view.at("editing_text").get<std::string>().empty())
      return FALSE;
    guarded(engine, "process_key", [&] {
      toggle_input_mode(engine);
    });
    return TRUE;
  }
  if (shift_key && !(flags & IBUS_RELEASE_MASK)) {
    // A modifier already held when Shift arrives makes this a chord.
    // Ignore Caps/Num Lock; IBus includes Shift in the modifier mask for
    // the Shift key event itself.
    s.pure_shift_candidate =
        s.mode_shift_enabled && s.focused && !s.blocked && chord_modifiers == 0;
    return FALSE;
  }
  if (ctrl_key && (flags & IBUS_RELEASE_MASK)) {
    if (!s.pure_ctrl_candidate || (chord_modifiers & ~IBUS_CONTROL_MASK)) {
      s.pure_ctrl_candidate = false;
      return FALSE;
    }
    s.pure_ctrl_candidate = false;
    if (!s.focused || s.blocked)
      return FALSE;
    if (!s.view.is_null() && !s.view.at("editing_text").get<std::string>().empty())
      return FALSE;
    guarded(engine, "process_key", [&] { toggle_input_mode(engine); });
    return TRUE;
  }
  if (ctrl_key && !(flags & IBUS_RELEASE_MASK)) {
    s.pure_shift_candidate = false;
    s.pure_ctrl_candidate =
        s.mode_ctrl_enabled && s.focused && !s.blocked &&
        (chord_modifiers & ~IBUS_CONTROL_MASK) == 0;
    return FALSE;
  }
  if (key == IBUS_space && release && s.mode_chord_held) {
    const bool ctrl_alt_space =
        (chord_modifiers & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK)) ==
            (IBUS_CONTROL_MASK | IBUS_MOD1_MASK) &&
        (chord_modifiers & ~(IBUS_CONTROL_MASK | IBUS_MOD1_MASK)) == 0;
    s.mode_chord_held = false;
    if (ctrl_alt_space) {
      return TRUE;
    }
  }
  if (flags & IBUS_RELEASE_MASK) {
    if (key == IBUS_space && s.voice_space_consumed) {
      s.voice_space_consumed = false;
      return TRUE;
    }
    if (s.voice_hotkey_consumed_key == key) {
      s.voice_hotkey_consumed_key = 0;
      if (s.voice_active && !s.voice_space_locked &&
          voice_hold_hotkey(s, key, chord_modifiers))
        guarded(engine, "voice_hotkey_release", [&] { voice_stop(engine); });
      return TRUE;
    }
    return FALSE;
  }
  s.pure_shift_candidate = false;
  s.pure_ctrl_candidate = false;
  const guint modifiers = flags & (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK |
                                   IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
                                   IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  const bool dedicated_english_toggle =
      (key == IBUS_e || key == IBUS_E) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK);
  const bool ctrl_alt_space =
      key == IBUS_space &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_MOD1_MASK);
  if (ctrl_alt_space && !s.mode_ctrl_alt_space_enabled)
    return FALSE;
  const bool mode_toggle =
      (key == IBUS_space &&
       (modifiers == IBUS_CONTROL_MASK ||
        ctrl_alt_space));
  const bool fullwidth_toggle = key == IBUS_space &&
                                modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK);
  const bool character_set_chord =
      (key == IBUS_f || key == IBUS_F) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK);
  if (character_set_chord && !s.character_set_shortcut_enabled)
    return FALSE;
  const bool character_set_toggle = character_set_chord;
  if (!s.focused || s.blocked || (!s.input_enabled && !mode_toggle && !fullwidth_toggle) ||
      (flags & IBUS_RELEASE_MASK))
    return FALSE;
  // Windows locks an active hold-to-record shortcut when Space is pressed.
  // IBus exposes the same interaction as key events; consume both halves of
  // the Space stroke so it cannot leak into the focused editor while voice
  // recognition is active. With the option disabled, Space follows the
  // regular editor/Engine path.
  if (s.voice_active && s.voice_hotkey_hold_space_lock && key == IBUS_space &&
      modifiers == 0) {
    s.voice_space_consumed = true;
    s.voice_space_locked = true;
    return TRUE;
  }
  if (character_set_toggle) {
    const auto configured_scheme = configured.at("preferences").value(
        "scheme", std::string("quanpin"));
    const auto active_scheme = s.scheme_override.value_or(configured_scheme);
    if (active_scheme == "japanese")
      return FALSE;
    guarded(engine, "toggle_character_set", [&] {
      s.open();
      if (!s.session)
        return;
      s.traditional_output = !s.traditional_output;
      s.traditional_output_override = s.traditional_output;
      render(engine, s.view);
      publish_mode(engine);
    });
    return TRUE;
  }
  if (fullwidth_toggle) {
    s.fullwidth = !s.fullwidth;
    guarded(engine, "toggle_character_width", [&] {
      s.open();
      if (s.session)
        apply(engine, msime_client_set_character_width(s.session, s.fullwidth));
      publish_mode(engine);
    });
    return TRUE;
  }
  if (modifier(key))
    return FALSE;
  if (key == IBUS_BackSpace) {
    if (s.last_smart_punctuation != 0) {
      s.smart_punctuation_rejected = s.last_smart_punctuation;
      s.last_smart_punctuation = 0;
      s.last_smart_punctuation_time = 0;
    }
  } else if (s.smart_punctuation_rejected != 0 &&
             s.smart_punctuation_rejected != static_cast<char>(key)) {
    s.smart_punctuation_rejected = 0;
  }
  bool handled = false;
  guarded(engine, "process_key", [&] {
    s.open();
    if (dedicated_english_toggle) {
      if (!s.session)
        return;
      const bool enabled = !s.english_mode;
      s.view = response(msime_client_set_english_mode(s.session, enabled));
      s.english_mode = enabled;
      s.dedicated_english_override = enabled;
      render(engine, s.view);
      publish_mode(engine);
      handled = true;
      return;
    }
    if (mode_toggle) {
      if (ctrl_alt_space && s.mode_chord_held) {
        handled = true;
        return;
      }
      if (ctrl_alt_space)
        s.mode_chord_held = true;
      toggle_input_mode(engine);
      handled = true;
      return;
    }
    if (!s.input_enabled)
      return;
    if (voice_hotkey(s, key, modifiers) && s.voice_enabled &&
        !s.voice_provider_socket.empty()) {
      if (s.voice_hotkey_consumed_key == key) {
        handled = true;
        return;
      }
      s.voice_hotkey_consumed_key = key;
      if (s.voice_active)
        voice_stop(engine);
      else
        voice_start(engine);
      handled = true;
      return;
    }
    if (key == IBUS_Escape && s.voice_active) {
      voice_cancel(engine);
      handled = true;
      return;
    }
    if (!s.view.at("focused").get<bool>())
      apply(engine, msime_client_focus(s.session, true));
    // Match Windows TSF: with CapsLock enabled, an uppercase letter at the
    // beginning of a fresh composition belongs to the editor. IBus exposes
    // the lock state in the modifier mask while preserving the uppercase
    // keysym, so leave that stroke untouched instead of opening a pinyin
    // composition.
    if ((flags & IBUS_LOCK_MASK) && key >= 'A' && key <= 'Z' &&
        s.view.at("editing_text").get<std::string>().empty() &&
        s.view.at("candidates").empty())
      return;
    // Apply configured candidate bindings before punctuation can consume them.
    if ((modifiers & ~IBUS_SHIFT_MASK) == 0 &&
        !s.view.at("candidates").empty()) {
      if (const auto edge = s.word_character.edge(key, (flags & IBUS_SHIFT_MASK) != 0)) {
        for (const auto &candidate : s.view.at("candidates")) {
          if (!candidate.at("highlighted").get<bool>()) continue;
          const auto &id = candidate.at("id");
          if (id.at("session").get<uint64_t>() != s.session) return;
          handled = apply(engine, msime_client_select_edge(
              s.session, id.at("generation").get<uint64_t>(),
              id.at("index").get<size_t>(), *edge));
          if (!handled)
            handled = apply(engine, msime_client_punctuation(
                s.session, static_cast<uint8_t>(key)));
          return;
        }
        return;
      }
      if (const auto navigation = s.navigation.command(
              key, (flags & IBUS_SHIFT_MASK) != 0)) {
        handled = apply(engine, msime_client_command(s.session, *navigation));
        return;
      }
    }
    // Disabled navigation keys belong to the application, including when a
    // composition is active. Do not fall through to the generic cancellation.
    if (msime::linux_host::navigation_key(key))
      return;
    if (modifiers == IBUS_CONTROL_MASK && key == IBUS_period) {
      s.chinese_punctuation = !s.chinese_punctuation;
      s.punctuation_override = s.chinese_punctuation;
      s.view = response(msime_client_set_chinese_punctuation(
          s.session, s.chinese_punctuation));
      render(engine, s.view);
      publish_mode(engine);
      handled = true;
      return;
    }
    if (flags &
        (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
         IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK)) {
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
      return;
    }
    if (s.number_row_selection && !s.view.value("nine_key", false) &&
        !s.view.at("candidates").empty()) {
      if (const auto index = candidate_digit_slot(key, keycode, flags, s.view)) {
        if (*index >= s.view.at("candidates").size()) return;
        const auto &candidate = s.view.at("candidates").at(*index);
        const auto &id = candidate.at("id");
        if (id.at("session").get<uint64_t>() != s.session) return;
        handled = apply(engine, msime_client_select(
            s.session, id.at("generation").get<uint64_t>(),
            id.at("index").get<size_t>()));
        return;
      }
    }
    if (const auto keypad = keypad_punctuation(key)) {
      const auto &editing_text = s.view.at("editing_text").get<std::string>();
      const auto &candidates = s.view.at("candidates");
      const bool has_composition = !editing_text.empty() ||
                                   (candidates.is_array() && !candidates.empty());
      if (*keypad == '.' || has_composition) {
        handled = apply(engine, msime_client_punctuation_ascii(
            s.session, static_cast<uint8_t>(*keypad)));
        if (!handled && *keypad == '.') {
          auto text = std::string(".");
          if (s.fullwidth)
            text = fullwidth_text(text);
          ibus_engine_commit_text(
              engine, ibus_text_new_from_string(text.c_str()));
          handled = true;
        }
      } else {
        // Arithmetic keypad marks keep the normal Engine punctuation policy
        // while remaining outside the configurable minus/equal paging keys.
        handled = apply(engine, msime_client_punctuation(
            s.session, static_cast<uint8_t>(*keypad)));
      }
      return;
    }
    if (microsoft_shuangpin_ing_key(s.view, key, modifiers)) {
      if (s.view.at("candidates").is_array() &&
          !s.view.at("candidates").empty() &&
          !apply(engine, msime_client_command(
                      s.session, MSIME_COMMIT_CANDIDATE)))
        return;
      handled = apply(engine, msime_client_character(s.session, ';', false));
      return;
    }
    if (unicode_plus_key(s.view, key, modifiers)) {
      if (s.view.at("candidates").is_array() &&
          !s.view.at("candidates").empty() &&
          !apply(engine, msime_client_command(
                      s.session, MSIME_COMMIT_CANDIDATE)))
        return;
      handled = apply(engine, msime_client_character(s.session, '+', true));
      return;
    }
    const auto &editing_text = s.view.at("editing_text").get<std::string>();
    if (s.chinese_punctuation && s.paired_punctuation &&
        !(flags & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) &&
        (key == IBUS_quotedbl ||
         (key == IBUS_apostrophe && editing_text.empty()))) {
      const auto pair_mode = key == IBUS_quotedbl
                                 ? PunctuationPairMode::DoubleQuote
                                 : PunctuationPairMode::SingleQuote;
      handled = apply(engine, msime_client_punctuation(
                                   s.session, static_cast<uint8_t>(key)),
                               pair_mode);
      if (handled)
        ibus_engine_forward_key_event(engine, IBUS_Left, 0, 0);
      return;
    }
    if (s.chinese_punctuation && s.paired_punctuation &&
        !(flags & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) &&
        (key == '(' || key == '[' || key == '<' || key == '{')) {
      const auto pair_mode = key == '{' ? PunctuationPairMode::Brace
                                        : PunctuationPairMode::Bracket;
      handled = apply(
          engine,
          key == '{'
              ? msime_client_punctuation_ascii(s.session, static_cast<uint8_t>(key))
              : msime_client_punctuation(s.session, static_cast<uint8_t>(key)),
          pair_mode);
      if (!handled && key == '{') {
        auto text = std::string("{}");
        if (s.fullwidth)
          text = fullwidth_text(std::move(text));
        ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
        handled = true;
      }
      if (handled)
        ibus_engine_forward_key_event(engine, IBUS_Left, 0, 0);
      return;
    }
    if (s.smart_punctuation_repeat && s.paired_punctuation && s.last_smart_punctuation == key &&
        s.last_smart_punctuation_time != 0 &&
        g_get_monotonic_time() - s.last_smart_punctuation_time <=
            kSmartPunctuationRepeatIntervalUs &&
        s.view.at("editing_text").get<std::string>().empty()) {
      if (const auto *replacement = smart_punctuation_pair(static_cast<char>(key))) {
        ibus_engine_delete_surrounding_text(engine, -1, 1);
        ibus_engine_commit_text(engine, ibus_text_new_from_static_string(replacement));
        s.last_smart_punctuation = 0;
        s.last_smart_punctuation_time = 0;
        handled = true;
        return;
        }
    }
    if (s.smart_punctuation && is_smart_punctuation_key(key) &&
        s.smart_punctuation_rejected != static_cast<char>(key) &&
        smart_punctuation_preceded_by_ascii_alphanumeric(s)) {
      const auto &editing_text = s.view.at("editing_text").get<std::string>();
      const auto &candidates = s.view.at("candidates");
      const bool has_composition = !editing_text.empty() ||
                                   (candidates.is_array() && !candidates.empty());
      if (has_composition) {
        handled = apply(engine, msime_client_punctuation_ascii(
                                  s.session, static_cast<uint8_t>(key)));
      } else {
        std::string text(1, static_cast<char>(key));
        if (s.fullwidth)
          text = fullwidth_text(text);
        ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
        if (s.paired_punctuation) {
          s.last_smart_punctuation = static_cast<char>(key);
          s.last_smart_punctuation_time = g_get_monotonic_time();
        }
        handled = true;
      }
      return;
    }
    if (!s.smart_punctuation && s.view.at("editing_text").get<std::string>().empty() &&
        std::string("`~!@#$%^&*()-_=+[]{}\\;:'\",.<>/?").find(key) !=
            std::string::npos) {
      auto text = std::string(1, static_cast<char>(key));
      if (s.fullwidth)
        text = fullwidth_text(text);
      ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
      handled = true;
      return;
    }
    const bool has_composition =
        !s.view.at("editing_text").get<std::string>().empty();
    const bool candidate_active =
        s.view.at("candidates").is_array() && !s.view.at("candidates").empty();
    const auto local_mode = s.view.value("local_mode", std::string("none"));
    const bool lowercase_letter =
        (key >= 'a' && key <= 'z');
    const bool uppercase_letter =
        (key >= 'A' && key <= 'Z');
    const auto active_scheme = s.scheme_override.value_or(
        configured.at("preferences").value("scheme", "quanpin"));
    const bool helpcode =
        (active_scheme == "quanpin" || active_scheme == "shuangpin") &&
        s.helpcode_override.value_or(
            configured.at("preferences")
                .value(active_scheme + "_helpcode", Json::object())
                .value("enabled", true));
    const bool accepted_letter =
        local_mode == "quick_phrase"
            ? lowercase_letter
            : local_mode == "unicode"
                  ? ((key >= 'a' && key <= 'f') ||
                     (key >= 'A' && key <= 'F'))
                  : local_mode == "date_time"
                        ? false
                        : (local_mode != "none" || lowercase_letter ||
                           (uppercase_letter && helpcode));
    const bool nine_key_digit =
        local_mode != "unicode" && s.view.value("nine_key", false) &&
        ((key >= IBUS_KP_2 && key <= IBUS_KP_9) ||
         (key >= '2' && key <= '9'));
    const bool unicode_digit =
        local_mode == "unicode" && key >= '0' && key <= '9' &&
        (modifiers & IBUS_SHIFT_MASK) == 0;
    const bool microsoft_ing =
        microsoft_shuangpin_ing_key(s.view, key, modifiers);
    const bool unicode_plus = unicode_plus_key(s.view, key, modifiers);
    const bool accepted_apostrophe =
        key == IBUS_apostrophe && has_composition &&
        ((local_mode == "none" && active_scheme != "wubi") ||
         local_mode == "emoji" || local_mode == "kaomoji" ||
         local_mode == "temporary_japanese");
    const bool candidate_input =
        candidate_active &&
        (accepted_letter || nine_key_digit || unicode_digit || microsoft_ing ||
         unicode_plus || accepted_apostrophe);
    if (candidate_input) {
      if (!apply(engine, msime_client_command(
                     s.session, MSIME_COMMIT_CANDIDATE)))
        return;
      if (microsoft_ing) {
        handled = apply(engine, msime_client_character(
                                   s.session, ';', false));
      } else if (unicode_plus) {
        handled = apply(engine, msime_client_character(
                                   s.session, '+', true));
      } else if (key >= IBUS_KP_0 && key <= IBUS_KP_9) {
        handled = apply(engine, msime_client_character(
                                   s.session,
                                   static_cast<uint8_t>('0' + key - IBUS_KP_0),
                                   false));
      } else {
        handled = apply(engine, msime_client_character(
            s.session, static_cast<uint8_t>(key),
            (flags & IBUS_SHIFT_MASK) != 0));
      }
      return;
    }
    const char ascii = static_cast<char>(key);
    if (key >= 0x21 && key <= 0x7e &&
        std::ispunct(static_cast<unsigned char>(ascii)) != 0 &&
        (ascii != '\'' || !has_composition)) {
      handled = apply(engine, msime_client_punctuation(
          s.session, static_cast<uint8_t>(ascii)));
      if (is_smart_punctuation_key(key))
        s.smart_punctuation_rejected = 0;
      return;
    }
    if (!s.view.at("candidates").empty() &&
        (key == IBUS_Home || key == IBUS_KP_Home || key == IBUS_End ||
         key == IBUS_KP_End)) {
      const auto command = (key == IBUS_Home || key == IBUS_KP_Home)
                               ? MSIME_FIRST_CANDIDATE_ON_PAGE
                               : MSIME_LAST_CANDIDATE_ON_PAGE;
      handled = apply(engine, msime_client_command(s.session, command));
      return;
    }
    uint32_t command = UINT32_MAX;
    switch (key) {
    case IBUS_BackSpace:
      command = candidate_active ? MSIME_CANCEL : MSIME_BACKSPACE;
      break;
    case IBUS_Return:
    case IBUS_KP_Enter:
      command = candidate_active ? MSIME_COMMIT_CANDIDATE : MSIME_COMMIT_RAW;
      break;
    case IBUS_Escape:
      command = MSIME_CANCEL;
      break;
    case IBUS_space:
      command = MSIME_COMMIT_CANDIDATE;
      break;
    case IBUS_Left:
    case IBUS_KP_Left:
      command = MSIME_MOVE_LEFT;
      break;
    case IBUS_Right:
    case IBUS_KP_Right:
      command = MSIME_MOVE_RIGHT;
      break;
    case IBUS_Home:
    case IBUS_KP_Home:
      command = MSIME_MOVE_HOME;
      break;
    case IBUS_End:
    case IBUS_KP_End:
      command = MSIME_MOVE_END;
      break;
    case IBUS_Delete:
    case IBUS_KP_Delete:
      command = candidate_active ? MSIME_CANCEL : MSIME_DELETE_FORWARD;
      break;
    }
    if (command != UINT32_MAX)
      handled = apply(engine, msime_client_command(s.session, command));
    else if (key >= IBUS_KP_0 && key <= IBUS_KP_9)
      handled = apply(
          engine,
          msime_client_character(
              s.session, static_cast<uint8_t>('0' + key - IBUS_KP_0), false));
    else if (key >= 0x21 && key <= 0x7e)
      handled = apply(engine, msime_client_character(
          s.session,
          static_cast<uint8_t>((flags & IBUS_SHIFT_MASK) && key >= 'a' &&
                                       key <= 'z'
                                   ? key - 'a' + 'A'
                                   : key),
          (flags & IBUS_SHIFT_MASK) != 0));
    else
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
  });
  return handled;
}
void candidate_clicked(IBusEngine *engine, guint index, guint button,
                       guint flags) {
  if ((button != 1 && button != 2 && button != 3) || flags || !state(engine).focused ||
      state(engine).blocked || !state(engine).input_enabled) return;
  guarded(engine, "candidate_clicked", [&] {
    auto &s = state(engine);
    const auto candidates = s.view.value("candidates", Json::array());
    if (!s.session || !candidates.is_array() || index >= candidates.size()) return;
    const auto &entry = candidates.at(index);
    if (!entry.is_object() || !entry.contains("id")) return;
    const auto &id = entry.at("id");
    if (!id.is_object() || id.at("session").get<uint64_t>() != s.session) return;
    const auto generation = id.at("generation").get<uint64_t>();
    const auto global_index = id.at("index").get<size_t>();
    const auto source = entry.value("source", 0);
    const auto scheme = s.view.value("scheme", 255);
    if (button == 3 && scheme != 3 &&
        (source == 0 || source == 1 || source == 4))
      apply(engine, msime_client_pin_candidate(s.session, generation, global_index));
    else if (button != 3)
      apply(engine, msime_client_select(s.session, generation, global_index));
  });
}
void page(IBusEngine *engine, uint32_t command) {
  guarded(engine, "page", [&] {
    auto &s = state(engine);
    if (s.session && s.focused && !s.blocked && s.input_enabled)
      apply(engine, msime_client_command(s.session, command));
  });
}
struct PreferencesRead {
  std::string directory;
  uint64_t session;
};
gboolean reload_preferences(gpointer data) {
  auto engine = IBUS_ENGINE(data);
  auto &s = state(engine);
  if (s.preferences_loading)
    return G_SOURCE_CONTINUE;
  const auto directory = configured.find("preferences_directory");
  if (directory == configured.end() || !directory->is_string() ||
      directory->get<std::string>().empty() ||
      directory->get<std::string>().front() != '/')
    return G_SOURCE_CONTINUE;
  s.preferences_loading = true;
  auto task = g_task_new(G_OBJECT(engine), nullptr,
                         +[](GObject *source, GAsyncResult *result, gpointer) {
                           auto self = reinterpret_cast<MsimePreviewEngine *>(source);
                           std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
                               static_cast<char *>(g_task_propagate_pointer(
                                   G_TASK(result), nullptr)),
                               msime_client_string_free);
                           if (!self->state)
                             return;
                           auto &s = *self->state;
                           s.preferences_loading = false;
                           const auto *request = static_cast<const PreferencesRead *>(
                               g_task_get_task_data(G_TASK(result)));
                           if (!request || !raw)
                             return;
                           try {
                             auto snapshot = response(raw.release());
                             if (snapshot.is_null())
                               return;
                             configured["preferences"] = snapshot.at("preferences");
                             const bool voice_socket_changed =
                                 s.refresh_provider_sockets();
                             if (request->session == 0 ||
                                 s.session != request->session || !s.focused ||
                                 s.blocked)
                               return;
                             s.apply_session_overrides(snapshot);
                             s.refresh_host_preferences(snapshot.at("preferences"));
                             sync_global_input_mode(IBUS_ENGINE(source));
                             if (voice_socket_changed && s.voice_active)
                               voice_cancel(IBUS_ENGINE(source));
                             if (s.voice_active && !s.voice_enabled)
                               voice_cancel(IBUS_ENGINE(source));
                             const auto encoded = snapshot.dump();
                             auto updated = response(msime_client_update_preferences(
                                 s.session,
                                 reinterpret_cast<const uint8_t *>(encoded.data()),
                                 encoded.size()));
                             s.view = updated.at("view");
                             render(IBUS_ENGINE(source), s.view);
                             publish_mode(IBUS_ENGINE(source));
                           } catch (...) {
                             // Retry on the next tick without logging paths or input.
                           }
                         },
                         nullptr);
  g_task_set_task_data(
      task,
      new PreferencesRead{directory->get<std::string>(), s.session},
      +[](gpointer value) { delete static_cast<PreferencesRead *>(value); });
  g_task_run_in_thread(
      task,
      +[](GTask *task, gpointer, gpointer data, GCancellable *) {
        const auto &path = static_cast<PreferencesRead *>(data)->directory;
        g_task_return_pointer(
            task,
            msime_client_try_load_preferences(
                reinterpret_cast<const uint8_t *>(path.data()), path.size()),
            +[](gpointer value) {
              msime_client_string_free(static_cast<char *>(value));
            });
      });
  g_object_unref(task);
  return G_SOURCE_CONTINUE;
}
void register_properties(IBusEngine *engine) {
  publish_mode(engine, true);
}
void destroy(IBusObject *object) {
  auto self = reinterpret_cast<MsimePreviewEngine *>(object);
  if (self->state && self->state->preferences_timer)
    g_source_remove(self->state->preferences_timer);
  delete self->state;
  self->state = nullptr;
  IBUS_OBJECT_CLASS(msime_preview_engine_parent_class)->destroy(object);
}
} // namespace

static void msime_preview_engine_init(MsimePreviewEngine *engine) {
  engine->state = new State();
  engine->state->preferences_timer =
      g_timeout_add(1000, reload_preferences, engine);
}
static void msime_preview_engine_class_init(MsimePreviewEngineClass *klass) {
  auto engine = IBUS_ENGINE_CLASS(klass);
  engine->process_key_event = process_key;
  engine->property_activate = property_activate;
  engine->focus_in = focus_in;
  engine->focus_out = focus_out;
  engine->disable = focus_out;
  engine->reset = reset;
  engine->set_content_type = content_type;
  engine->set_surrounding_text = set_surrounding;
  engine->candidate_clicked = candidate_clicked;
  engine->page_up = [](IBusEngine *e) { page(e, MSIME_PREVIOUS_PAGE); };
  engine->page_down = [](IBusEngine *e) { page(e, MSIME_NEXT_PAGE); };
  engine->cursor_up = [](IBusEngine *e) { page(e, MSIME_PREVIOUS_CANDIDATE); };
  engine->cursor_down = [](IBusEngine *e) { page(e, MSIME_NEXT_CANDIDATE); };
  IBUS_OBJECT_CLASS(klass)->destroy = destroy;
}
void msime_preview_configure(const std::string &options) {
  if (options.size() > 16384 || msime_client_abi_version() != 1)
    throw std::runtime_error("Invalid host configuration");
  configured = Json::parse(options);
}

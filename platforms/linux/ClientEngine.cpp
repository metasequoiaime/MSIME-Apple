#include "ClientEngine.h"
#include "KeyRouterAdapter.h"
#include "ClipboardText.h"
#include "ChineseTextConversion.h"
#include "NavigationBindings.h"
#include "NativeCompose.h"
#include "WordCharacterBinding.h"
#include "VoiceAction.h"
#include "VoiceWorker.h"
#include "WaveOverlayModel.h"
#include "WaveOverlayIbusSurface.h"
#include "WaveOverlaySurfaceFactory.h"
#include "msime_client.h"
#include <algorithm>
#include <atomic>
#include <array>
#include <cctype>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <fcntl.h>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <set>
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
uint64_t configuration_generation = 0;
std::atomic<uint64_t> next_client_token{1};
// Store acceptance is shared by all contexts and survives session recreation.
// Effective runtime revisions also include local overrides and are independent.
std::string accepted_preferences_directory;
Json accepted_preferences_snapshot;
bool menu_save_pending = false;
uint64_t menu_status_generation = 0;

bool system_dark = false;
Json skin_display_preferences(Json preferences) {
  if (preferences.value("candidate_theme", "follow") == "follow")
    preferences["candidate_theme"] = system_dark ? "dark" : "light";
  const auto selected = preferences.value("candidate_skin", "fluent");
  if (selected == "fluent" || selected == "wechat" || selected == "graphite" ||
      selected == "willow_green")
    return preferences;
  const auto catalog = configured.find("candidate_skin_catalog");
  if (catalog == configured.end() || !catalog->is_object())
    return preferences;
  const auto packages = catalog->find("packages");
  if (packages == catalog->end() || !packages->is_array())
    return preferences;
  for (const auto &package : *packages) {
    if (!package.is_object() || package.value("id", std::string{}) != selected)
      continue;
    const auto candidate = package.value("candidate", Json::object());
    if (!candidate.is_object()) break;
    const auto theme = preferences.value("candidate_theme", "follow") == "dark" ? "dark" : "light";
    const auto palette = candidate.value(theme, Json::object());
    if (!palette.is_object()) break;
    if (!preferences.value("candidate_text_color", Json(nullptr)).is_string() &&
        palette.contains("text"))
      preferences["candidate_text_color"] = palette["text"];
    if (!preferences.value("candidate_number_color", Json(nullptr)).is_string() &&
        palette.contains("number"))
      preferences["candidate_number_color"] = palette["number"];
    if (palette.contains("surface"))
      preferences["candidate_background_color"] = palette["surface"];
    break;
  }
  return preferences;
}
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
std::optional<guint> candidate_number_color(const Json &preferences);
std::optional<guint> candidate_background_color(const Json &preferences);
IBusOrientation candidate_orientation(const Json &preferences);
std::string preedit_style(const Json &preferences);
bool launch_desktop_panel(const char *panel);
enum class MenuPreference { Toolbar, CloudCandidates, CandidateTranslations, TranslationLanguage, CandidateTheme, PreeditStyle, CandidateLayout, CandidateSkin, CandidatePageSize, FrequencyMode, SmartPunctuation, SmartPunctuationRepeat, PairedPunctuation, PunctuationLock, AutocorrectTransposition, AutocorrectNeighbor, EnglishCandidates, EmojiCandidates, KaomojiCandidates, QuanpinHelpcode, ShuangpinHelpcode, QuanpinHelpcodeSchema, ShuangpinHelpcodeSchema, ShuangpinProfile, InputScheme, NineKey, LocalMode, NumberRowSelection, WordCharacter, TraditionalOutput, ChinesePunctuation, ClipboardHistoryEnabled, InputMode, CharacterWidth, VoiceEnabled };
void save_menu_preference(IBusEngine *engine, MenuPreference preference, Json value);
struct FailedMenuSave {
  MenuPreference preference;
  Json value;
  std::string directory;
  uint64_t configuration;
};
std::optional<FailedMenuSave> failed_menu_save;

void voice_cancel(IBusEngine *engine);
std::string configured_clipboard_path(const Json &options) {
  const auto explicit_path = options.value("clipboard_history_path", std::string{});
  if (!explicit_path.empty())
    return explicit_path;
  const auto directory = options.value("preferences_directory", std::string{});
  if (directory.empty() || directory.front() != '/')
    return {};
  return (std::filesystem::path(directory) / "clipboard_history.json").string();
}
std::string provider_socket_fallback(const Json &options, const char *option,
                                      const char *environment, const char *filename) {
  auto value = options.value(option, std::string{});
  if (!value.empty())
    return value;
  if (const auto *socket = g_getenv(environment); socket && *socket)
    return socket;
  const auto *runtime = g_get_user_runtime_dir();
  if (!runtime || !*runtime)
    return {};
  const auto candidate = std::filesystem::path(runtime) / "msime-client" / filename;
  std::error_code error;
  return std::filesystem::is_socket(candidate, error) ? candidate.string() : std::string{};
}
struct State;
bool script_conversion_applies(const Json &context);
std::string traditional_display(const State &s, const Json &context,
                                std::string text);
struct State {
  msime::linux_host::NativeCompose native_compose;
  MsimeVoiceWorker voice_worker;
  uint64_t session = 0;
  uint64_t client_token = 0;
  uint64_t focus_epoch = 0;
  msime::linux_host::KeyRouterAdapter key_router;
  Json view;
  bool focused = false;
  std::string focused_context;
  bool blocked = false;
  bool private_input = false;
  guint preferences_timer = 0;
  bool preferences_loading = false;
  uint64_t seen_menu_status_generation = 0;
  uint64_t seen_menu_configuration = 0;
  bool input_enabled = true;
  bool mode_scope_global = false;
  bool chinese_punctuation = true;
  bool properties_registered = false;
  std::optional<bool> english_override;
  std::optional<bool> dedicated_english_override;
  std::optional<bool> cloud_candidates_override;
  std::optional<bool> candidate_translations_override;
  std::optional<bool> traditional_output_override;
  std::optional<bool> emoji_override;
  std::optional<bool> kaomoji_override;
  std::optional<bool> punctuation_override, helpcode_override;
  std::optional<bool> autocorrect_transposition_override, autocorrect_neighbor_override;
  bool show_helpcode_in_candidate_window = true;
  std::optional<bool> word_character_override;
  std::optional<bool> smart_punctuation_override, smart_repeat_override, paired_punctuation_override;
  std::optional<std::string> punctuation_lock_override;
  std::optional<uint8_t> candidate_page_size_override;
  std::optional<std::string> frequency_mode_override, helpcode_schema_override;
  std::optional<std::string> layout_override, preedit_override, theme_override;
  std::optional<std::string> skin_override, scheme_override, shuangpin_profile_override;
  std::optional<std::string> translation_target_language_override;
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
  bool shift_down = false;
  bool ctrl_down = false;
  bool right_ctrl_down = false;
  bool left_ctrl_down = false;
  bool mode_chord_held = false;
  std::set<guint> host_shortcut_strokes;
  gint64 modifier_toggle_deadline = 0;
  void reset_mode_modifiers() {
    pure_shift_candidate = false;
    pure_ctrl_candidate = false;
    shift_down = false;
    ctrl_down = false;
    right_ctrl_down = false;
    left_ctrl_down = false;
    modifier_toggle_deadline = 0;
    mode_chord_held = false;
    host_shortcut_strokes.clear();
  }
  bool mode_shift_enabled = true;
  bool mode_ctrl_enabled = false;
  bool mode_ctrl_alt_space_enabled = true;
  bool character_set_shortcut_enabled = true;
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
  std::optional<guint> candidate_number_color;
  IBusOrientation candidate_orientation = IBUS_ORIENTATION_VERTICAL;
  msime::linux_host::NavigationBindings navigation;
  msime::linux_host::WordCharacterBinding word_character;
  std::string ai_context;
  void remember_commit(const std::string &text) {
    if (!focused || blocked || private_input) {
      ai_context.clear();
      return;
    }
    ai_context += text;
    if (ai_context.size() > 1024) {
      size_t cut = ai_context.size() - 1024;
      while (cut < ai_context.size() &&
             (static_cast<unsigned char>(ai_context[cut]) & 0xc0) == 0x80)
        ++cut;
      ai_context.erase(0, cut);
    }
  }
  std::string clipboard_history_path, online_provider_socket,
      translation_provider_socket;
  std::string voice_provider_socket, voice_language = "zh-cn";
  bool voice_enabled = true;
  bool voice_hotkey_ralt = true;
  bool voice_hotkey_ctrl_win = false;
  bool voice_hotkey_rctrl_ralt = false;
  bool voice_hotkey_hold_space_lock = true;
  bool voice_hotkey_ctrl_f9 = true;
  // Key ownership lasts until release, independently of provider completion.
  std::set<guint> voice_consumed_keys;
  guint voice_hold_key = 0;
  bool voice_space_consumed = false;
  bool voice_space_locked = false;
  bool voice_active = false;
  bool voice_stopping = false;
  bool voice_requires_control = false;
  uint64_t voice_generation = 0;
  std::string voice_preedit;
  std::string voice_transcript;
  std::string voice_phase = "正在录音…";
  std::optional<unsigned> voice_level;
  msime::linux_host::WaveOverlayModel wave_overlay;
  std::unique_ptr<msime::linux_host::WaveOverlaySurface> wave_overlay_surface;
  bool wave_overlay_visible = false;
  std::shared_ptr<std::atomic_bool> alive =
      std::make_shared<std::atomic_bool>(true);
  std::vector<std::string> clipboard_items_cache;
  uint64_t clipboard_generation = 0;
  bool clipboard_loading = false, clipboard_loaded = false;
  bool clipboard_enabled = true;
  uint64_t applied_preferences_revision = 0;
  uint64_t applied_display_generation = 0;
  Json applied_preferences_snapshot;
  GFileMonitor *clipboard_monitor = nullptr;
  GFile *clipboard_watch_file = nullptr;
  void stop_clipboard_monitor() {
    if (clipboard_monitor) {
      g_file_monitor_cancel(clipboard_monitor);
      g_clear_object(&clipboard_monitor);
    }
    g_clear_object(&clipboard_watch_file);
  }
  void configure_clipboard(std::string path, bool enabled) {
    if (!path.empty() && path.front() != '/')
      path.clear();
    if (path == clipboard_history_path && enabled == clipboard_enabled)
      return;
    stop_clipboard_monitor();
    ++clipboard_generation;
    clipboard_loaded = false;
    clipboard_items_cache.clear();
    clipboard_history_path = std::move(path);
    clipboard_enabled = enabled;
  }
  std::array<bool, 2> online_loading{};
  bool translation_loading = false;
  guint online_delay_source = 0;
  guint translation_delay_source = 0;
  bool cloud_candidates = true;
  bool candidate_translations = true;
  bool translation_reset_pending = false;
  std::string translation_target_language = "en";
  uint64_t provider_epoch = 0;
  std::string translation_dispatched_query;
  std::array<std::string, 2> online_dispatched_query;
  void invalidate_providers() {
    if (online_delay_source) {
      const auto source = online_delay_source;
      online_delay_source = 0;
      g_source_remove(source);
    }
    if (translation_delay_source) {
      const auto source = translation_delay_source;
      translation_delay_source = 0;
      g_source_remove(source);
    }
    ++provider_epoch;
    online_loading.fill(false);
    translation_loading = false;
    translation_dispatched_query.clear();
    for (auto &query : online_dispatched_query) query.clear();
  }
  std::string surrounding_text;
  bool surrounding_utf16 = false;
  // Preserve client units until use: focus identity may arrive after text.
  guint surrounding_cursor = 0;
  guint surrounding_anchor = 0;
  ~State() {
    alive->store(false);
    close();
  }
  void close() {
    translation_reset_pending = false;
    applied_preferences_revision = 0;
    applied_preferences_snapshot = nullptr;
    stop_clipboard_monitor();
    ai_context.clear();
    if (voice_active && !voice_provider_socket.empty())
      msime_client_string_free(msime_client_voice_provider_cancel(
          reinterpret_cast<const uint8_t *>(voice_provider_socket.data()),
          voice_provider_socket.size(), voice_generation));
    if (voice_active && session)
      msime_client_string_free(msime_client_voice_cancel(session));
    voice_active = false;
    voice_generation = 0;
    voice_preedit.clear();
    voice_transcript.clear();
    wave_overlay = {};
    voice_consumed_keys.clear();
    voice_hold_key = 0;
    voice_space_consumed = false;
    voice_space_locked = false;
    reset_mode_modifiers();
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
    fullwidth = preferences.value("character_width", "halfwidth") == "fullwidth";
    if (layout_override) preferences["candidate_layout"] = *layout_override;
    if (preedit_override) preferences["tsf_preedit_style"] = *preedit_override;
    if (theme_override) preferences["candidate_theme"] = *theme_override;
    if (skin_override) preferences["candidate_skin"] = *skin_override;
    // Default snapshots omit the empty quanpin override object.
    if (!preferences.contains("quanpin"))
      preferences["quanpin"] = Json::object();
    auto &quanpin = preferences["quanpin"];
    if (autocorrect_transposition_override)
      quanpin["autocorrect_transposition"] = *autocorrect_transposition_override;
    if (autocorrect_neighbor_override)
      quanpin["autocorrect_neighbor"] = *autocorrect_neighbor_override;
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
    configure_clipboard(configured_clipboard_path(options),
                        preferences.value("clipboard_history", false));
    online_provider_socket = provider_socket_fallback(
        options, "online_provider_socket", "MSIME_ONLINE_PROVIDER_SOCKET", "online.sock");
    translation_provider_socket =
        options.value("translation_provider_socket", std::string{});
    if (translation_provider_socket.empty()) {
      if (const auto *socket = g_getenv("MSIME_TRANSLATION_PROVIDER_SOCKET"))
        translation_provider_socket = socket;
    }
    if (translation_provider_socket.empty())
      translation_provider_socket = online_provider_socket;
    voice_provider_socket = provider_socket_fallback(
        options, "voice_provider_socket", "MSIME_VOICE_PROVIDER_SOCKET", "voice.sock");
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
    candidate_translations = candidate_translations_override.value_or(
        preferences.value("candidate_translations", true));
    translation_target_language = translation_target_language_override.value_or(
        preferences.value("translation_target_language", "en"));
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
    options.erase("candidate_skin_catalog");
    auto encoded = options.dump();
    auto bindings =
        msime::linux_host::NavigationBindings::read(options.at("preferences"));
    auto edge_binding = msime::linux_host::WordCharacterBinding::read(
        options.at("preferences"));
    view = response(msime_client_create(
        reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    session = view.at("session").get<uint64_t>();
    view = response(msime_client_set_character_width(session, fullwidth));
    // CN/EN passthrough defaults are independent of the English candidate mode.
    english_mode = dedicated_english_override.value_or(false);
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
    const auto display_preferences = skin_display_preferences(options.at("preferences"));
    candidate_text_color = ::candidate_text_color(display_preferences);
    candidate_number_color = ::candidate_number_color(display_preferences);
    candidate_background_color = ::candidate_background_color(display_preferences);
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
    configure_clipboard(configured_clipboard_path(configured),
                        preferences.value("clipboard_history", false));
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
    fullwidth = preferences.value("character_width", "halfwidth") == "fullwidth";
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
    const bool next_candidate_translations = candidate_translations_override.value_or(
        preferences.value("candidate_translations", true));
    if (next_candidate_translations != candidate_translations) {
      translation_reset_pending = true;
      invalidate_providers();
    }
    candidate_translations = next_candidate_translations;
    const auto next_translation_target_language = translation_target_language_override.value_or(
        preferences.value("translation_target_language", "en"));
    if (next_translation_target_language != translation_target_language) {
      translation_reset_pending = true;
      invalidate_providers();
    }
    translation_target_language = next_translation_target_language;
    auto display_preferences = preferences;
    if (layout_override)
      display_preferences["candidate_layout"] = *layout_override;
    if (theme_override)
      display_preferences["candidate_theme"] = *theme_override;
    if (skin_override)
      display_preferences["candidate_skin"] = *skin_override;
    display_preferences = skin_display_preferences(std::move(display_preferences));
    candidate_text_color = ::candidate_text_color(display_preferences);
    candidate_number_color = ::candidate_number_color(display_preferences);
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
  bool refresh_provider_sockets(IBusEngine *engine) {
    const auto online = provider_socket_fallback(
        configured, "online_provider_socket", "MSIME_ONLINE_PROVIDER_SOCKET", "online.sock");
    const auto translation = [&] {
      auto socket = configured.value("translation_provider_socket", std::string{});
      if (socket.empty()) {
        if (const auto *value = g_getenv("MSIME_TRANSLATION_PROVIDER_SOCKET"))
          socket = value;
      }
      return socket.empty() ? online : socket;
    }();
    const auto voice = provider_socket_fallback(
        configured, "voice_provider_socket", "MSIME_VOICE_PROVIDER_SOCKET", "voice.sock");
    const bool voice_changed = voice != voice_provider_socket;
    const bool online_changed = online != online_provider_socket ||
                                translation != translation_provider_socket;
    if (translation != translation_provider_socket)
      translation_reset_pending = true;
    // Cancel against the old endpoint before replacing it, so the previous
    // provider does not keep recording after an environment/config change.
    if (voice_changed && voice_active)
      voice_cancel(engine);
    if (online_changed)
      invalidate_providers();
    online_provider_socket = online;
    translation_provider_socket = translation;
    voice_provider_socket = voice;
    return voice_changed || online_changed;
  }
  void apply_session_overrides(Json &options) const {
    auto &preferences = options["preferences"];
    if (cloud_candidates_override)
      preferences["cloud_candidates"] = *cloud_candidates_override;
    if (candidate_translations_override)
      preferences["candidate_translations"] = *candidate_translations_override;
    if (translation_target_language_override)
      preferences["translation_target_language"] = *translation_target_language_override;
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
    if (!preferences.contains("quanpin"))
      preferences["quanpin"] = Json::object();
    auto &quanpin = preferences["quanpin"];
    if (autocorrect_transposition_override)
      quanpin["autocorrect_transposition"] = *autocorrect_transposition_override;
    if (autocorrect_neighbor_override)
      quanpin["autocorrect_neighbor"] = *autocorrect_neighbor_override;
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
      if (items.size() == 50) break;
      if (!entry.is_string()) continue;
      auto text = entry.get<std::string>();
      if (text.size() > 12000) continue;
      if (!text.empty()) items.push_back(std::move(text));
    }
  } catch (...) {}
  return items;
}
bool clipboard_delete(const std::string &path, const std::optional<std::string> &text) {
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
    if (!text) {
      std::error_code error;
      std::filesystem::remove(path, error);
      removed = !error;
    } else {
      std::ifstream input{std::filesystem::path(path)};
      auto value = Json::parse(input);
      if (value.is_array()) {
        const auto entry = std::find(value.begin(), value.end(), Json(*text));
        if (entry == value.end()) {
          flock(lock, LOCK_UN);
          close(lock);
          return true;
        }
        value.erase(entry);
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
    }
  } catch (...) {
  }
  flock(lock, LOCK_UN);
  close(lock);
  return removed;
}
State &state(IBusEngine *engine);
// Record the exact text sent to IBus after each route's output conversion.
void commit_text(IBusEngine *engine, const std::string &text) {
  if (text.empty())
    return;
  ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
  state(engine).remember_commit(text);
}
void publish_mode(IBusEngine *engine, bool registration = false);
void sync_global_input_mode(IBusEngine *engine);
void voice_cancel(IBusEngine *engine);
bool launch_desktop_panel(const char *panel) {
  const auto *command = g_getenv("MSIME_CLIENT_SETTINGS_COMMAND");
  if (!command || !*command)
    command = "msime-client-settings";
  gchar *argv[] = {const_cast<gchar *>(command), nullptr};
  gchar **environment = g_get_environ();
  const bool about = std::string(panel) == "about";
  environment = g_environ_setenv(environment, "MSIME_CLIENT_PANEL", about ? "settings" : panel, TRUE);
  // A settings section travels as "settings:<category>"; the bare section name
  // is not a route head and would be rejected by the shared parser.
  environment = g_environ_setenv(
      environment, "MSIME_CLIENT_ROUTE", about ? "settings:about" : panel, TRUE);
  if (about)
    environment = g_environ_setenv(environment, "MSIME_CLIENT_SETTINGS_PAGE", "about", TRUE);
  GError *error = nullptr;
  const auto started = g_spawn_async(
      nullptr, argv, environment, G_SPAWN_SEARCH_PATH, nullptr, nullptr,
      nullptr, &error);
  g_strfreev(environment);
  if (error)
    g_error_free(error);
  return started != FALSE;
}
bool restart_ibus_service() {
  gchar *argv[] = {const_cast<gchar *>("ibus"),
                   const_cast<gchar *>("restart"), nullptr};
  GError *error = nullptr;
  const auto started = g_spawn_async(nullptr, argv, nullptr,
                                     G_SPAWN_SEARCH_PATH, nullptr, nullptr,
                                     nullptr, &error);
  if (error)
    g_error_free(error);
  return started != FALSE;
}

struct DesktopPanelAction {
  const char *property;
  const char *panel;
  const char *label;
};
constexpr DesktopPanelAction desktop_panel_actions[] = {
    {"DesktopTools/Handwriting", "handwriting", "手写识别板"},
    {"DesktopTools/Keyboard", "keyboard", "屏幕键盘"},
    {"DesktopTools/Emoji", "emoji", "表情与符号"},
    {"DesktopTools/Clipboard", "clipboard", "本地剪贴板"},
    {"DesktopTools/Voice", "voice", "语音面板"},
    {"DesktopTools/CloudDictionary", "cloud-dictionary", "云词典"},
    {"DesktopTools/CloudClipboard", "cloud-clipboard", "云剪贴板"},
    {"DesktopTools/Settings", "settings", "设置"},
    {"DesktopTools/About", "about", "关于"},
};

IBusProperty *desktop_tools_property(IBusEngine *engine) {
  const auto &s = state(engine);
  auto items = ibus_prop_list_new();
  const auto directory = configured.value("preferences_directory", std::string{});
  const bool can_retry = failed_menu_save &&
      failed_menu_save->directory == directory &&
      failed_menu_save->configuration == configuration_generation;
  ibus_prop_list_append(items, ibus_property_new(
      "DesktopTools/RetrySave", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string(menu_save_pending ? "正在保存设置…" : "设置未保存，点击重试"), "",
      ibus_text_new_from_static_string("重新读取最新设置并重试上次菜单修改"),
      can_retry && !menu_save_pending && s.focused && !s.blocked,
      menu_save_pending || can_retry, PROP_STATE_UNCHECKED, nullptr));
  const bool toolbar_enabled = configured.at("preferences")
      .value("floating_toolbar", Json::object()).value("enabled", true);
  ibus_prop_list_append(items, ibus_property_new(
      "DesktopTools/ToolbarEnabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("工具栏"), "",
      ibus_text_new_from_static_string("保存工具栏显示开关"),
      s.focused && !s.blocked && !menu_save_pending &&
          !directory.empty() && directory.front() == '/',
      TRUE, toolbar_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr));
  for (const auto &action : desktop_panel_actions) {
    ibus_prop_list_append(items, ibus_property_new(
        action.property, PROP_TYPE_NORMAL,
        ibus_text_new_from_static_string(action.label), "",
        ibus_text_new_from_static_string(action.label),
        s.focused && !s.blocked &&
            (std::string(action.property) != "DesktopTools/Voice" || s.voice_enabled),
        TRUE, PROP_STATE_UNCHECKED, nullptr));
  }
  ibus_prop_list_append(items, ibus_property_new(
      "DesktopTools/VoiceEnabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("启用语音输入"), "",
      ibus_text_new_from_static_string("启用或停用语音快捷键和录音入口"),
      s.focused && !s.blocked && !menu_save_pending && !directory.empty() &&
          directory.front() == '/',
      TRUE, s.voice_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr));
  return ibus_property_new(
      "DesktopTools", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("桌面工具"), "",
      ibus_text_new_from_static_string("打开水杉桌面面板"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, items);
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
      ibus_text_new_from_static_string("Linux 原生输入法工具栏"), available,
      toolbar.value("enabled", true),
      PROP_STATE_UNCHECKED, items);
}

struct ClipboardTask {
  std::string path;
  uint64_t generation;
};
void clipboard_schedule(IBusEngine *engine);
void watch_clipboard_history(IBusEngine *engine) {
  auto &s = state(engine);
  const auto previous_path = s.clipboard_history_path;
  s.configure_clipboard(configured_clipboard_path(configured),
                        s.clipboard_enabled);
  if (previous_path != s.clipboard_history_path && s.focused && !s.blocked)
    publish_mode(engine);
  if (!s.clipboard_enabled || !s.focused || s.blocked || !s.input_enabled ||
      s.clipboard_history_path.empty()) {
    s.stop_clipboard_monitor();
    return;
  }
  auto target = g_file_new_for_path(s.clipboard_history_path.c_str());
  if (s.clipboard_monitor && !g_file_monitor_is_cancelled(s.clipboard_monitor) &&
      s.clipboard_watch_file && g_file_equal(target, s.clipboard_watch_file)) {
    g_object_unref(target);
    return;
  }
  s.stop_clipboard_monitor();
  auto parent = g_file_get_parent(target);
  if (!parent) {
    g_object_unref(target);
    return;
  }
  // Watch the directory so atomic replace and delete/recreate keep working.
  s.clipboard_monitor = g_file_monitor_directory(
      parent, G_FILE_MONITOR_WATCH_MOVES, nullptr, nullptr);
  g_object_unref(parent);
  if (!s.clipboard_monitor) {
    g_object_unref(target);
    return;
  }
  s.clipboard_watch_file = target;
  g_file_monitor_set_rate_limit(s.clipboard_monitor, 100);
  g_signal_connect(s.clipboard_monitor, "changed",
      G_CALLBACK(+[](GFileMonitor *, GFile *file, GFile *other,
                     GFileMonitorEvent, gpointer data) {
        auto engine = IBUS_ENGINE(data);
        auto &s = state(engine);
        if (!s.clipboard_enabled || !s.clipboard_watch_file || !s.focused || s.blocked || !s.input_enabled)
          return;
        if ((!file || !g_file_equal(file, s.clipboard_watch_file)) &&
            (!other || !g_file_equal(other, s.clipboard_watch_file)))
          return;
        ++s.clipboard_generation;
        s.clipboard_loaded = false;
        s.clipboard_items_cache.clear();
        publish_mode(engine);
      }), engine);
  // A monitor may have been unavailable when the directory did not exist.
  // Reload after attaching to close that gap.
  ++s.clipboard_generation;
  s.clipboard_loaded = false;
  clipboard_schedule(engine);
}
void clipboard_complete(GObject *source, GAsyncResult *result, gpointer);
void clipboard_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.clipboard_enabled || s.clipboard_history_path.empty() || s.clipboard_loading || !s.focused ||
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
std::optional<guint> palette_color(const Json &value) {
  if (!value.is_string()) return std::nullopt;
  const auto hex = value.get<std::string>();
  if (hex.size() != 7 || hex.front() != '#') return std::nullopt;
  guint color = 0;
  for (size_t index = 1; index < hex.size(); ++index) {
    const auto c = static_cast<unsigned char>(hex[index]);
    guint digit;
    if (c >= '0' && c <= '9') digit = c - '0';
    else if (c >= 'a' && c <= 'f') digit = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') digit = c - 'A' + 10;
    else return std::nullopt;
    color = (color << 4) | digit;
  }
  return color;
}
std::optional<guint> candidate_text_color(const Json &preferences) {
  if (const auto custom = palette_color(preferences.value("candidate_text_color", Json(nullptr))))
    return custom;
  const auto background = candidate_background_color(preferences);
  if (!background) return std::nullopt;
  const auto linear = [](guint channel) {
    const double value = channel / 255.0;
    return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
  };
  const auto luminance = 0.2126 * linear((*background >> 16) & 0xff) +
                         0.7152 * linear((*background >> 8) & 0xff) +
                         0.0722 * linear(*background & 0xff);
  const auto black_contrast = (luminance + 0.05) / 0.05;
  const auto white_contrast = 1.05 / (luminance + 0.05);
  return black_contrast >= white_contrast ? 0x000000u : 0xffffffu;
}
std::optional<guint> candidate_number_color(const Json &preferences) {
  return palette_color(preferences.value("candidate_number_color", Json(nullptr)));
}
std::optional<guint> candidate_background_color(const Json &preferences) {
  if (const auto custom = palette_color(preferences.value("candidate_background_color", Json(nullptr))))
    return custom;
  if (const auto custom = palette_color(preferences.value("candidate_surface_color", Json(nullptr))))
    return custom;
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
std::size_t surrounding_byte_offset(const State &s, guint offset) {
  const auto *utf8 = s.surrounding_text.c_str();
  const auto *position = utf8;
  // IBus uses code points; QIBusInputContext forwards QString UTF-16 units.
  while (*position) {
    const guint units = s.surrounding_utf16 &&
                        g_utf8_get_char(position) > 0xffff ? 2 : 1;
    if (offset < units)
      break;
    offset -= units;
    position = g_utf8_next_char(position);
  }
  return static_cast<std::size_t>(position - utf8);
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
  // A commit replaces the selection, so inspect the character before its start.
  const auto cursor = surrounding_byte_offset(
      s, std::min(s.surrounding_cursor, s.surrounding_anchor));
  if (cursor == 0)
    return false;
  const auto value = static_cast<unsigned char>(surrounding[cursor - 1]);
  // A UTF-8 continuation byte means the preceding code point is non-ASCII.
  return value < 0x80 && is_ascii_alphanumeric(value);
}
bool smart_punctuation_repeat_matches_document(const State &s) {
  if (s.surrounding_cursor != s.surrounding_anchor)
    return false;
  auto previous = std::string(1, s.last_smart_punctuation);
  if (s.fullwidth)
    previous = fullwidth_text(std::move(previous));
  const auto cursor = surrounding_byte_offset(s, s.surrounding_cursor);
  return cursor >= previous.size() &&
         s.surrounding_text.compare(cursor - previous.size(), previous.size(),
                                    previous) == 0;
}
constexpr gint64 kSmartPunctuationRepeatIntervalUs = 2 * G_USEC_PER_SEC;

struct OnlineTask {
  uint64_t session;
  uint64_t epoch;
  std::string query;
  std::string socket;
  std::string provider_query;
  uint8_t source;
};
struct TranslationTask {
  uint64_t session;
  uint64_t epoch;
  std::string query;
  std::string socket;
  std::string resources;
  std::string gloss_query;
  bool offline = false;
  Json local_translations = Json::array();
};
bool apply(IBusEngine *engine, char *raw,
           PunctuationPairMode pair_mode = PunctuationPairMode::None);
void render(IBusEngine *engine, const Json &view);
void apply_live_preferences(IBusEngine *engine, Json snapshot);
void sync_translation_preferences(IBusEngine *engine) {
  auto &s = state(engine);
  apply_live_preferences(engine, Json{
      {"format_version", 1},
      {"preferences", s.applied_preferences_snapshot.is_object()
                          ? s.applied_preferences_snapshot
                          : configured.at("preferences")}});
}
void clear_candidate_translations(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.session || !s.view.is_object())
    return;
  constexpr uint8_t empty[] = {'[', ']'};
  auto result = response(msime_client_apply_translations(
      s.session, s.view.value("generation", uint64_t{0}), empty, sizeof(empty)));
  s.view = result.at("view");
  s.translation_reset_pending = false;
  render(engine, s.view);
}
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
void start_translation_task(IBusEngine *engine, TranslationTask request) {
  auto *task_data = new TranslationTask(std::move(request));
  state(engine).translation_loading = true;
  auto task = g_task_new(G_OBJECT(engine), nullptr, translation_complete, nullptr);
  g_task_set_task_data(task, task_data, [](gpointer value) { delete static_cast<TranslationTask *>(value); });
  g_task_run_in_thread(task, [](GTask *task, gpointer, gpointer data, GCancellable *) {
    auto &request = *static_cast<TranslationTask *>(data);
    auto *raw = request.offline
        ? msime_client_candidate_gloss_request(
              reinterpret_cast<const uint8_t *>(request.gloss_query.data()), request.gloss_query.size(),
              reinterpret_cast<const uint8_t *>(request.resources.data()), request.resources.size())
        : msime_client_translation_provider_request(
              reinterpret_cast<const uint8_t *>(request.query.data()), request.query.size(),
              reinterpret_cast<const uint8_t *>(request.socket.data()), request.socket.size());
    // Persistence is display-data I/O and stays on this worker. View updates
    // still pass the session/epoch/generation checks in translation_complete.
    if (!request.offline && raw) {
      try {
        const auto query = Json::parse(request.query);
        const auto result = Json::parse(raw);
        const auto user_data = Json::parse(request.gloss_query).value("user_data", std::string{});
        if (query.value("target_language", std::string{}) == "en" &&
            result.value("ok", false) && !user_data.empty()) {
          const auto save = Json{{"target_language", "en"},
                                 {"translations", result.at("value").at("translations")}}.dump();
          msime_client_string_free(msime_client_translation_gloss_save(
              reinterpret_cast<const uint8_t *>(save.data()), save.size(),
              reinterpret_cast<const uint8_t *>(user_data.data()), user_data.size()));
        }
      } catch (...) {}
    }
    g_task_return_pointer(task, raw, [](gpointer value) { msime_client_string_free(static_cast<char *>(value)); });
  });
  g_object_unref(task);
}
void translation_dispatch(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.candidate_translations ||
      (s.translation_provider_socket.empty() && s.translation_target_language != "en") ||
      s.translation_loading || !s.session ||
      !s.focused || s.blocked || !s.input_enabled ||
      !s.view.value("candidates", Json::array()).size())
    return;
  try {
    auto query = response(msime_client_translation_query(s.session));
    if (query.is_null() || !query.is_object()) return;
    query["target_language"] = s.translation_target_language;
    // The shared query carries candidate objects; the socket protocol takes
    // the candidate texts, matching TranslationQuery in the host API.
    auto texts = Json::array();
    for (const auto &candidate : query.at("candidates"))
      texts.push_back(candidate.at("text"));
    query["candidates"] = std::move(texts);
    const auto encoded = query.dump();
    // Applying a gloss redraws the same generation. Do not start another
    // provider request until the query or provider configuration changes.
    if (encoded == s.translation_dispatched_query) return;
    s.translation_dispatched_query = encoded;
    auto candidates = Json::array();
    for (const auto &candidate : s.view.at("candidates"))
      candidates.push_back({{"text", candidate.at("text")}, {"source", candidate.at("source")}});
    const auto gloss_query = Json{{"generation", query.at("generation")},
                                  {"user_data", configured.value("user_data", std::string{})},
                                  {"candidates", candidates}}.dump();
    start_translation_task(engine, TranslationTask{
        s.session, s.provider_epoch, encoded, s.translation_provider_socket,
        configured.value("resources", std::string{}), gloss_query,
        s.translation_target_language == "en", Json::array()});
  } catch (...) { s.translation_loading = false; }
}
// Match the Windows translation worker's 500ms idle window. Only copy
// the current Engine query when dispatching, never at the first keystroke.
void translation_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.translation_delay_source) {
    const auto source = s.translation_delay_source;
    s.translation_delay_source = 0;
    g_source_remove(source);
  }
  if (!s.candidate_translations ||
      (s.translation_provider_socket.empty() && s.translation_target_language != "en") ||
      !s.session || !s.focused || s.blocked || !s.input_enabled ||
      s.view.value("candidates", Json::array()).empty())
    return;
  s.translation_delay_source = g_timeout_add_full(
      G_PRIORITY_DEFAULT, 500,
      [](gpointer data) -> gboolean {
        auto *engine = IBUS_ENGINE(data);
        state(engine).translation_delay_source = 0;
        translation_dispatch(engine);
        return G_SOURCE_REMOVE;
      },
      g_object_ref(engine), [](gpointer data) { g_object_unref(data); });
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
void online_dispatch(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_provider_socket.empty() || !s.session ||
      !s.focused || s.blocked || !s.input_enabled)
    return;
  try {
    auto query = response(msime_client_online_query(s.session));
    if (query.is_object()) {
      query["cloud_candidates"] = s.cloud_candidates;
      if (s.applied_preferences_snapshot.is_object()) {
        const auto desired = s.applied_preferences_snapshot.value("ai_assistant", Json::object());
        const auto current = query.value("ai_assistant", Json::object());
        bool matches = desired.value("enabled", false) && current.value("enabled", false);
        // Engine preference application may be deferred until composition
        // ends. Never launch another request with the superseded AI settings.
        for (const auto *key : {"provider", "model", "endpoint", "candidate_limit",
                                "prompt_id", "prompt", "prompt_custom_1",
                                "prompt_custom_2", "prompt_custom_3"}) {
          if (desired.contains(key) &&
              (!current.contains(key) || desired.at(key) != current.at(key)))
            matches = false;
        }
        if (!matches) {
          // Eligibility is part of Engine's response identity. Remove the
          // provider configuration rather than changing that identity.
          query.erase("ai_assistant");
        }
      }
    }
    if (!query.is_object()) return;
    const auto ai = query.value("ai_assistant", Json::object());
    const bool ai_requested = query.value("ai_eligible", false) &&
                              ai.is_object() && ai.value("enabled", false);
    if (!(s.cloud_candidates && query.value("cloud_eligible", false)) && !ai_requested)
      return;
    if (!s.private_input && ai_requested)
      query["ai_context"] = s.ai_context;
    const auto encoded = query.dump();
    // Keep the original Engine identity for application, while each transport
    // request enables only one source. Fast cloud results need not wait for AI.
    std::vector<std::unique_ptr<OnlineTask>> requests;
    for (uint8_t source = 0; source < 2; ++source) {
      // Each source has one in-flight request and its own duplicate guard.
      // A pending AI result must not delay cloud for a newer composition.
      if (s.online_loading[source] || encoded == s.online_dispatched_query[source]) continue;
      if (source == 0 && !(s.cloud_candidates && query.value("cloud_eligible", false))) continue;
      if (source == 1 && !ai_requested) continue;
      auto provider_query = query;
      if (source == 0) {
        provider_query.erase("ai_assistant");
        provider_query.erase("ai_context");
      } else {
        provider_query["cloud_candidates"] = false;
      }
      requests.push_back(std::make_unique<OnlineTask>(OnlineTask{
          s.session, s.provider_epoch, encoded, s.online_provider_socket,
          provider_query.dump(), source}));
    }
    for (auto &request : requests) {
      s.online_dispatched_query[request->source] = encoded;
      s.online_loading[request->source] = true;
      auto task = g_task_new(G_OBJECT(engine), nullptr, online_complete, nullptr);
      g_task_set_task_data(task, request.release(), [](gpointer value) {
        delete static_cast<OnlineTask *>(value);
      });
      g_task_run_in_thread(task, [](GTask *task, gpointer, gpointer data, GCancellable *) {
        auto &request = *static_cast<OnlineTask *>(data);
        auto *raw = msime_client_online_provider_request(
            reinterpret_cast<const uint8_t *>(request.provider_query.data()), request.provider_query.size(),
            reinterpret_cast<const uint8_t *>(request.socket.data()), request.socket.size());
        g_task_return_pointer(task, raw, [](gpointer value) {
          msime_client_string_free(static_cast<char *>(value));
        });
      });
      g_object_unref(task);
    }
  } catch (...) {}
}
// Match Windows cloud_ime's 500ms idle delay without sleeping on the
// IBus input thread. Read the latest Engine query only when the timer fires.
void online_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_delay_source) {
    const auto source = s.online_delay_source;
    s.online_delay_source = 0;
    g_source_remove(source);
  }
  if (s.online_provider_socket.empty() || !s.session || !s.focused ||
      s.blocked || !s.input_enabled)
    return;
  s.online_delay_source = g_timeout_add_full(
      G_PRIORITY_DEFAULT, 500,
      [](gpointer data) -> gboolean {
        auto *engine = IBUS_ENGINE(data);
        state(engine).online_delay_source = 0;
        online_dispatch(engine);
        return G_SOURCE_REMOVE;
      },
      g_object_ref(engine), [](gpointer data) { g_object_unref(data); });
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
  auto translations = request->local_translations;
  if (raw) {
    try {
      const auto document = Json::parse(raw.get());
      if (document.value("ok", false)) {
        const auto &value = document.at("value");
        if (value.is_object())
          for (const auto &item : value.at("translations"))
            translations.push_back(item);
      }
    } catch (...) {}
  }
  try {
    auto query = Json::parse(request->query);
    const auto generation = query.at("generation").get<uint64_t>();
    const auto encoded = translations.dump();
    auto applied = response(msime_client_apply_translations(
        s.session, generation, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    s.view = applied.at("view");
    render(engine, s.view);
    // Publish local hits before starting network work, and only send misses.
    if (request->offline && !request->socket.empty()) {
      auto missing = Json::array();
      for (const auto &text : query.at("candidates")) {
        const bool found = std::any_of(translations.begin(), translations.end(),
            [&](const Json &item) { return item.at("text") == text; });
        if (!found) missing.push_back(text);
      }
      if (!missing.empty()) {
        query["candidates"] = std::move(missing);
        auto next = *request;
        next.query = query.dump();
        next.offline = false;
        next.local_translations = std::move(translations);
        start_translation_task(engine, std::move(next));
      }
    }
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
  if (!request || request->source >= s.online_loading.size() ||
      request->session != s.session || request->epoch != s.provider_epoch)
    return;
  s.online_loading[request->source] = false;
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
    if (!value.is_object()) return;
    const auto candidates = value.value("candidates", Json::array({value}));
    if (!candidates.is_array() || candidates.size() > 11) return;
    Json groups[2] = {Json::array(), Json::array()};
    for (const auto &item : candidates) {
      const auto candidate = item.value("text", std::string{});
      const auto source = item.value("source", 255);
      if (candidate.empty() || source != request->source ||
          (!s.cloud_candidates && source == 0)) continue;
      groups[source].push_back(candidate);
    }
    for (uint8_t source = 0; source < 2; ++source) {
      if (groups[source].empty()) continue;
      const auto encoded = groups[source].dump();
      auto applied = response(msime_client_apply_online_candidates(
          s.session, reinterpret_cast<const uint8_t *>(request->query.data()), request->query.size(),
          reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size(), source));
      s.view = applied.at("view");
    }
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
  if (!s.clipboard_enabled || request->generation != s.clipboard_generation || !s.focused || s.blocked ||
      request->path != s.clipboard_history_path) {
    delete items;
    clipboard_schedule(IBUS_ENGINE(source));
    return;
  }
  if (!items)
    return;
  ++s.clipboard_generation;
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
          "", ibus_text_new_from_static_string("选择九键拼音"), TRUE, TRUE,
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
  const bool actions_available = s.focused && !s.blocked && s.input_enabled && s.session;
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
    auto actions = ibus_prop_list_new();
    auto preview = candidate.value("text", std::string{});
    msime_clipboard_truncate(preview, 48);
    const auto entry_label = std::to_string(slot) + ". " + preview;
    const auto entry_name = candidate_action_name("CandidateEntry", id);
    auto entry = ibus_property_new(
        entry_name.c_str(), PROP_TYPE_MENU,
        ibus_text_new_from_string(entry_label.c_str()), "",
        ibus_text_new_from_static_string("选择此候选的操作"), actions_available, TRUE,
        PROP_STATE_UNCHECKED, actions);
    ibus_prop_list_append(items, entry);
    const auto fixed_position = candidate.value("fixed_position", 0);
    for (const auto &[action, label] : {std::pair{"CandidatePin", "固定候选"},
                                       std::pair{"CandidateRemove", "删除候选"},
                                       std::pair{"CandidateFix1", "固定到 1"},
                                       std::pair{"CandidateFix2", "固定到 2"},
                                       std::pair{"CandidateFix3", "固定到 3"},
                                       std::pair{"CandidateFix4", "固定到 4"},
                                       std::pair{"CandidateFix5", "固定到 5"}}) {
      const auto name = candidate_action_name(action, candidate.at("id"));
      const auto title = std::string(label) + " " + std::to_string(slot);
      const auto state = g_str_has_prefix(action, "CandidateFix") &&
                                 fixed_position ==
                                     std::stoi(std::string(action).substr(12))
                             ? PROP_STATE_CHECKED
                             : PROP_STATE_UNCHECKED;
      ibus_prop_list_append(actions, ibus_property_new(
          name.c_str(), PROP_TYPE_NORMAL, ibus_text_new_from_string(title.c_str()), "",
          ibus_text_new_from_static_string("操作当前页候选"), actions_available, TRUE,
          state, nullptr));
    }
    const auto clear_name = candidate_action_name("CandidateClear", candidate.at("id"));
    ibus_prop_list_append(actions, ibus_property_new(
        clear_name.c_str(), PROP_TYPE_NORMAL,
        ibus_text_new_from_string((std::string("取消固定 ") + std::to_string(slot)).c_str()), "",
        ibus_text_new_from_static_string("取消当前候选的位置固定"), fixed_position > 0, TRUE,
        PROP_STATE_UNCHECKED, nullptr));
  }
  return ibus_property_new("CandidateActions", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选操作"), "",
      ibus_text_new_from_static_string("固定或删除当前页候选"),
      s.session && s.focused && !s.blocked && s.input_enabled && editable_candidates,
      TRUE, PROP_STATE_UNCHECKED, items);
}
void publish_mode(IBusEngine *engine, bool registration) {
  auto &s = state(engine);
  if (s.skin_override) {
    const auto selected = *s.skin_override;
    bool available = selected == "fluent" || selected == "wechat" ||
                     selected == "graphite" || selected == "willow_green";
    if (!available) {
      const auto catalog = configured.find("candidate_skin_catalog");
      if (catalog != configured.end() && catalog->is_object()) {
        const auto packages = catalog->find("packages");
        if (packages != catalog->end() && packages->is_array())
          for (const auto &package : *packages)
            if (package.is_object() && package.value("id", std::string{}) == selected)
              available = true;
      }
    }
    if (!available) s.skin_override.reset();
  }
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
  const auto quanpin_preferences = configured.at("preferences").value(
      "quanpin", Json::object());
  const bool autocorrect_transposition = s.autocorrect_transposition_override.value_or(
      quanpin_preferences.value("autocorrect_transposition",
          configured.at("preferences").value("autocorrect", true)));
  const bool autocorrect_neighbor = s.autocorrect_neighbor_override.value_or(
      quanpin_preferences.value("autocorrect_neighbor",
          configured.at("preferences").value("autocorrect", true)));
  const auto active_scheme = s.scheme_override.value_or(
      configured.at("preferences").value("scheme", "quanpin"));
  const bool nine_key = active_scheme == "quanpin" && s.view.is_object() &&
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
  const auto voice_label = s.voice_active
      ? (s.voice_space_locked && !s.voice_stopping
             ? std::string("录音已锁定") : s.voice_phase)
      : std::string("语音输入");
  auto voice = ibus_property_new(
      "VoiceInput", PROP_TYPE_TOGGLE,
      ibus_text_new_from_string(voice_label.c_str()), "",
      ibus_text_new_from_static_string("点击开始录音，再次点击结束录音并提交识别结果；Esc 取消"),
      s.focused && !s.blocked && s.input_enabled && s.voice_enabled &&
          !s.voice_provider_socket.empty() && !(s.voice_active && s.voice_stopping),
      TRUE, s.voice_active ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto voice_cancel_property = ibus_property_new(
      "VoiceCancel", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string("取消语音输入"), "",
      ibus_text_new_from_static_string("取消当前录音、识别或润色，不提交语音结果"),
      s.focused && !s.blocked && s.input_enabled && s.session && s.voice_active,
      s.voice_active, PROP_STATE_UNCHECKED, nullptr);
  auto cloud = ibus_property_new(
      "CloudCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("云联想"), "",
      ibus_text_new_from_static_string("通过用户管理的 provider 请求云候选"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !s.online_provider_socket.empty() && !menu_save_pending,
      TRUE, s.cloud_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto translations = ibus_property_new(
      "CandidateTranslations", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("候选翻译"), "",
      ibus_text_new_from_static_string("通过用户管理的 provider 请求候选翻译"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !s.translation_provider_socket.empty() && !menu_save_pending,
      TRUE, s.candidate_translations ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto translation_language = ibus_property_new(
      "TranslationLanguage", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("翻译目标语言"), "",
      ibus_text_new_from_static_string("选择候选翻译的目标语言"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !s.translation_provider_socket.empty() && !menu_save_pending,
      TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto translation_language_menu = ibus_prop_list_new();
  const bool translation_available = s.focused && !s.blocked && s.input_enabled &&
      s.session && !s.translation_provider_socket.empty() && !menu_save_pending;
  for (const auto &[value, label] : {std::pair{"en", "英语"},
                                     std::pair{"fr", "法语"},
                                     std::pair{"ja", "日语"},
                                     std::pair{"es", "西班牙语"},
                                     std::pair{"ru", "俄语"},
                                     std::pair{"de", "德语"},
                                     std::pair{"ko", "韩语"}}) {
    auto item = ibus_property_new(
        (std::string("TranslationLanguage/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("切换候选翻译目标语言"), translation_available, TRUE,
        s.translation_target_language == value ? PROP_STATE_CHECKED
                                                : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(translation_language_menu, item);
  }
  ibus_property_set_sub_props(translation_language, translation_language_menu);
  auto punctuation = ibus_property_new(
      "Punctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("切换中文或英文标点"),
      s.focused && !s.blocked && s.input_enabled && s.session && !menu_save_pending, TRUE,
      s.chinese_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto smart_punctuation = ibus_property_new(
      "SmartPunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("智能标点"), "",
      ibus_text_new_from_static_string("按上下文选择标点形式"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      s.smart_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto smart_repeat = ibus_property_new(
      "SmartPunctuationRepeat", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("重复标点转中文"), "",
      ibus_text_new_from_static_string("短时间重复输入 ASCII 标点时替换为中文标点"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      s.smart_punctuation_repeat ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto paired = ibus_property_new(
      "PairedPunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("成对标点"), "",
      ibus_text_new_from_static_string("输入成对引号和括号"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      s.paired_punctuation ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto punctuation_lock = ibus_property_new(
      "PunctuationLock", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("标点锁定"), "",
      ibus_text_new_from_static_string("跟随输入模式或固定中文/英文标点"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto punctuation_lock_menu = ibus_prop_list_new();
  const bool punctuation_available = s.focused && !s.blocked && s.input_enabled &&
      s.session && !menu_save_pending;
  for (const auto &[value, label] : {std::pair{"follow", "跟随"},
                                     std::pair{"chinese", "固定中文"},
                                     std::pair{"english", "固定英文"}}) {
    auto item = ibus_property_new(
        (std::string("PunctuationLock/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择标点锁定策略"), punctuation_available, TRUE,
        s.punctuation_lock == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(punctuation_lock_menu, item);
  }
  ibus_property_set_sub_props(punctuation_lock, punctuation_lock_menu);
  auto character_mode = ibus_property_new(
      "CharacterMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("全角字符"), "",
      ibus_text_new_from_static_string("切换 ASCII 全角或半角输出"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      s.fullwidth ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto traditional = ibus_property_new(
      "TraditionalOutput", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("繁体输出"), "",
      ibus_text_new_from_static_string("将中文候选和上屏文本转换为繁体"),
      s.focused && !s.blocked && s.input_enabled && s.session &&
          !japanese_scheme && !menu_save_pending,
      TRUE, s.traditional_output ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto english = ibus_property_new(
      "EnglishCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充英文候选"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      english_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto english_mode = ibus_property_new(
      "EnglishMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文输入模式"), "",
      ibus_text_new_from_static_string("切换 Engine 的独立英文输入模式（Ctrl+Shift+E）"),
      s.focused && !s.blocked && s.input_enabled && s.session, TRUE,
      s.english_mode ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto autocorrect_transposition_property = ibus_property_new(
      "AutocorrectTransposition", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("拼音错位纠错"), "",
      ibus_text_new_from_static_string("纠正拼音字母顺序错位"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      autocorrect_transposition ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto autocorrect_neighbor_property = ibus_property_new(
      "AutocorrectNeighbor", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("拼音邻键纠错"), "",
      ibus_text_new_from_static_string("纠正相邻键误触"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      autocorrect_neighbor ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto helpcode_property = ibus_property_new(
      "Helpcode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("辅助码"), "",
      ibus_text_new_from_static_string("启用候选辅助码提示"),
      s.focused && !s.blocked && s.input_enabled &&
          (active_scheme == "quanpin" || active_scheme == "shuangpin") && !menu_save_pending, TRUE,
      helpcode ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto helpcode_schema = ibus_property_new(
      "HelpcodeSchema", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("辅助码方案"), "",
      ibus_text_new_from_static_string("选择辅助码编码方案"),
      s.focused && !s.blocked && s.input_enabled &&
          (active_scheme == "quanpin" || active_scheme == "shuangpin") && !menu_save_pending, TRUE,
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
        ibus_text_new_from_static_string("切换辅助码方案"),
        s.focused && !s.blocked && s.input_enabled &&
            (active_scheme == "quanpin" || active_scheme == "shuangpin") &&
            !menu_save_pending,
        TRUE,
        schema == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(helpcode_schema_menu, item);
  }
  ibus_property_set_sub_props(helpcode_schema, helpcode_schema_menu);
  auto emoji = ibus_property_new(
      "EmojiCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("Emoji 候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充 Emoji 候选"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      emoji_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto kaomoji = ibus_property_new(
      "KaomojiCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("颜文字候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充颜文字候选"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      kaomoji_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  const bool clipboard_available = s.clipboard_enabled && s.input_enabled &&
                                   !s.clipboard_history_path.empty();
  const bool clipboard_menu_available = s.focused && !s.blocked &&
                                       clipboard_available;
  auto clipboard = ibus_property_new(
      "ClipboardHistory", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("剪贴板历史"), "",
      ibus_text_new_from_static_string("浏览、提交和管理最近 50 条历史文本"),
      s.focused && !s.blocked,
      TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto clipboard_menu = ibus_prop_list_new();
  auto clipboard_toggle = ibus_property_new(
      "ClipboardHistory/Enabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("启用历史采集"), "",
      ibus_text_new_from_static_string("启用或停用本地剪贴板历史记录"),
      s.focused && !s.blocked && !menu_save_pending &&
          !configured.value("preferences_directory", std::string{}).empty(), TRUE,
      s.clipboard_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(clipboard_menu, clipboard_toggle);
  auto open_clipboard = ibus_property_new(
      "ClipboardHistory/OpenPanel", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string("打开历史面板"), "",
      ibus_text_new_from_static_string("搜索、管理或主动开启本地剪贴板历史"),
      s.focused && !s.blocked, TRUE, PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(clipboard_menu, open_clipboard);
  const auto &items = s.clipboard_items_cache;
  auto refresh_clipboard = ibus_property_new(
      "ClipboardHistory/Refresh", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string("刷新历史"), "",
      ibus_text_new_from_static_string("重新加载本地历史列表"),
      clipboard_menu_available && !s.clipboard_loading, TRUE, PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(clipboard_menu, refresh_clipboard);
  IBusPropList *page = nullptr;
  for (size_t index = 0; clipboard_available && index < items.size(); ++index) {
    if (index % 10 == 0) {
      page = ibus_prop_list_new();
      const auto label = std::to_string(index + 1) + "–" +
                         std::to_string(std::min(index + 10, items.size()));
      auto group = ibus_property_new(
          (std::string("ClipboardHistoryPage/") + std::to_string(index / 10)).c_str(),
          PROP_TYPE_MENU, ibus_text_new_from_string(label.c_str()), "",
          ibus_text_new_from_static_string("浏览这一组历史"), clipboard_menu_available, TRUE,
          PROP_STATE_UNCHECKED, page);
      ibus_prop_list_append(clipboard_menu, group);
    }
    auto preview = items[index];
    for (char &character : preview) {
      if (character == '\r' || character == '\n' || character == '\t')
        character = ' ';
    }
    msime_clipboard_truncate(preview, 48);
    const auto label = std::to_string(index + 1) + ". " + preview;
    const auto identity = std::to_string(s.clipboard_generation) + "/" + std::to_string(index);
    auto item = ibus_property_new(
        (std::string("ClipboardHistory/") + identity).c_str(),
        PROP_TYPE_NORMAL, ibus_text_new_from_string(label.c_str()), "",
        ibus_text_new_from_static_string("提交历史文本"), clipboard_menu_available, TRUE,
        PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(page, item);
    auto remove = ibus_property_new(
        (std::string("ClipboardHistory/Remove/") + identity).c_str(),
        PROP_TYPE_NORMAL,
        ibus_text_new_from_string((std::string("删除 ") + std::to_string(index + 1)).c_str()),
        "", ibus_text_new_from_static_string("删除这一条历史文本"), clipboard_menu_available, TRUE,
        PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(page, remove);
  }
  auto clear_clipboard = ibus_property_new(
      "ClipboardHistory/Clear", PROP_TYPE_NORMAL,
      ibus_text_new_from_static_string("清空历史"), "",
      ibus_text_new_from_static_string("删除本地剪贴板历史文件"),
      clipboard_menu_available && !items.empty(), TRUE, PROP_STATE_UNCHECKED, nullptr);
  ibus_prop_list_append(clipboard_menu, clear_clipboard);
  ibus_property_set_sub_props(clipboard, clipboard_menu);
  auto layout_property = ibus_property_new(
      "CandidateLayout", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选布局"), "",
      ibus_text_new_from_static_string("选择候选排列方向"),
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto layout_menu = ibus_prop_list_new();
  const bool policy_available = s.focused && !s.blocked && s.input_enabled &&
      s.session && !menu_save_pending;
  auto vertical = ibus_property_new(
      "CandidateLayout/Vertical", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("竖排"), "",
      ibus_text_new_from_static_string("竖直排列候选"), policy_available, TRUE,
      layout == "vertical" ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  auto horizontal = ibus_property_new(
      "CandidateLayout/Horizontal", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("横排"), "",
      ibus_text_new_from_static_string("水平排列候选"), policy_available, TRUE,
      layout == "horizontal" ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
      nullptr);
  ibus_prop_list_append(layout_menu, vertical);
  ibus_prop_list_append(layout_menu, horizontal);
  ibus_property_set_sub_props(layout_property, layout_menu);
  auto page_size_property = ibus_property_new(
      "CandidatePageSize", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选数量"), "",
      ibus_text_new_from_static_string("选择每页显示的候选数量"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED,
      nullptr);
  auto page_size_menu = ibus_prop_list_new();
  const auto page_size = s.candidate_page_size_override.value_or(
      configured.at("preferences").value("candidate_page_size", 5));
  for (uint8_t value = 1; value <= 9; ++value) {
    auto item = ibus_property_new(
        (std::string("CandidatePageSize/") + std::to_string(value)).c_str(),
        PROP_TYPE_RADIO, ibus_text_new_from_string(std::to_string(value).c_str()),
        "", ibus_text_new_from_static_string("设置候选页大小"), policy_available, TRUE,
        page_size == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(page_size_menu, item);
  }
  ibus_property_set_sub_props(page_size_property, page_size_menu);
  auto frequency_property = ibus_property_new(
      "FrequencyMode", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("词频调节"), "",
      ibus_text_new_from_static_string("选择学习词频调节策略"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED,
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
        ibus_text_new_from_static_string("设置词频调节模式"), policy_available, TRUE,
        frequency == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(frequency_menu, item);
  }
  ibus_property_set_sub_props(frequency_property, frequency_menu);
  auto number_row_property = ibus_property_new(
      "NumberRowSelection", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("数字选词"), "",
      ibus_text_new_from_static_string("使用数字键选择候选词"),
      s.focused && !s.blocked && s.input_enabled && !nine_key && !menu_save_pending, TRUE,
      s.number_row_selection && !nine_key ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto nine_key_property = ibus_property_new(
      "NineKey", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("九键输入"), "",
      ibus_text_new_from_static_string("使用数字键输入全拼并选择拼音候选"),
      s.focused && !s.blocked && s.input_enabled && active_scheme == "quanpin" && !menu_save_pending,
      TRUE, nine_key ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto nine_key_spellings_property = nine_key_spellings(engine);
  auto local_modes_property = ibus_property_new(
      "LocalModes", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("本地输入模式"), "",
      ibus_text_new_from_static_string("启用或停用本地快捷输入模式"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED,
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
    const bool enabled = s.local_mode_overrides.contains(key)
                             ? s.local_mode_overrides.at(key).get<bool>()
                             : configured_local_modes.value(key, true);
    auto item = ibus_property_new(
        (std::string("LocalModes/") + key).c_str(), PROP_TYPE_TOGGLE,
        ibus_text_new_from_static_string(label), "",
        ibus_text_new_from_static_string("本地快捷输入模式"),
        s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
        enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(local_modes_menu, item);
  }
  ibus_property_set_sub_props(local_modes_property, local_modes_menu);
  auto word_character_property = ibus_property_new(
      "WordCharacter", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("以词定字"), "",
      ibus_text_new_from_static_string("使用减号/等号或方括号选择词语首末汉字"),
      s.focused && !s.blocked && s.input_enabled && !menu_save_pending, TRUE,
      s.word_character.enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  auto preedit_property = ibus_property_new(
      "PreeditStyle", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("预编辑显示"), "",
      ibus_text_new_from_static_string("选择预编辑显示方式"),
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto preedit_menu = ibus_prop_list_new();
  const std::pair<const char *, const char *> preedit_options[] = {
      {"raw", "编码"}, {"pinyin", "拼音"}, {"empty", "隐藏"}};
  for (const auto &[value, label] : preedit_options) {
    auto item = ibus_property_new(
        (std::string("PreeditStyle/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择预编辑显示方式"), !menu_save_pending, TRUE,
        preedit == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(preedit_menu, item);
  }
  ibus_property_set_sub_props(preedit_property, preedit_menu);
  auto theme_property = ibus_property_new(
      "CandidateTheme", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选主题"), "",
      ibus_text_new_from_static_string("选择候选背景主题"),
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto theme_menu = ibus_prop_list_new();
  const std::pair<const char *, const char *> theme_options[] = {
      {"follow", "跟随系统"}, {"light", "浅色"}, {"dark", "深色"}};
  for (const auto &[value, label] : theme_options) {
    auto item = ibus_property_new(
        (std::string("CandidateTheme/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择候选主题"), !menu_save_pending, TRUE,
        theme == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(theme_menu, item);
  }
  ibus_property_set_sub_props(theme_property, theme_menu);
  auto skin_property = ibus_property_new(
      "CandidateSkin", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("候选皮肤"), "",
      ibus_text_new_from_static_string("选择候选窗口皮肤"),
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto skin_menu = ibus_prop_list_new();
  std::set<std::string> listed_skins{"fluent", "wechat", "graphite", "willow_green"};
  const std::pair<const char *, const char *> skin_options[] = {
      {"fluent", "Fluent"}, {"wechat", "微信绿"},
      {"graphite", "Graphite"}, {"willow_green", "杨柳青"}};
  for (const auto &[value, label] : skin_options) {
    auto item = ibus_property_new(
        (std::string("CandidateSkin/") + value).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("选择候选窗口皮肤"), !menu_save_pending, TRUE,
        skin == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
    ibus_prop_list_append(skin_menu, item);
  }
  if (const auto catalog = configured.find("candidate_skin_catalog");
      catalog != configured.end() && catalog->is_object()) {
    if (const auto packages = catalog->find("packages");
        packages != catalog->end() && packages->is_array()) {
      for (const auto &package : *packages) {
        const auto id = package.value("id", std::string{});
        if (id.empty() || !listed_skins.insert(id).second) continue;
        const auto title = package.value("title", id);
        ibus_prop_list_append(skin_menu, ibus_property_new(
            (std::string("CandidateSkin/") + id).c_str(), PROP_TYPE_RADIO,
            ibus_text_new_from_string(title.c_str()), "",
            ibus_text_new_from_static_string("外部候选皮肤"), !menu_save_pending, TRUE,
            skin == id ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr));
      }
    }
  }
  if (listed_skins.count(skin) == 0) {
    auto item = ibus_property_new(
        (std::string("CandidateSkin/") + skin).c_str(), PROP_TYPE_RADIO,
        ibus_text_new_from_string((std::string("外部：") + skin).c_str()), "",
        ibus_text_new_from_static_string("当前配置的皮肤不在可用目录中"), FALSE, TRUE,
        PROP_STATE_CHECKED, nullptr);
    ibus_prop_list_append(skin_menu, item);
  }
  ibus_property_set_sub_props(skin_property, skin_menu);
  auto scheme = ibus_property_new(
      "Scheme", PROP_TYPE_MENU,
      ibus_text_new_from_static_string("输入方案"), "",
      ibus_text_new_from_static_string("选择中文或日文输入方案"),
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
  auto scheme_menu = ibus_prop_list_new();
  auto chinese = ibus_property_new(
      "Scheme/Chinese", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("中文"), "",
      ibus_text_new_from_static_string("使用当前中文方案"), !menu_save_pending, TRUE,
      japanese_scheme ? PROP_STATE_UNCHECKED : PROP_STATE_CHECKED, nullptr);
  auto japanese = ibus_property_new(
      "Scheme/Japanese", PROP_TYPE_RADIO,
      ibus_text_new_from_static_string("日文"), "",
      ibus_text_new_from_static_string("使用日语罗马字方案"), !menu_save_pending, TRUE,
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
        ibus_text_new_from_static_string("直接选择中文输入方案"), !menu_save_pending, TRUE,
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
      s.focused && !s.blocked && !menu_save_pending, TRUE, PROP_STATE_UNCHECKED, nullptr);
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
        ibus_text_new_from_static_string("切换双拼键位方案"), !menu_save_pending, TRUE,
        configured_profile == value ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(profile_menu, item);
  }
  ibus_property_set_sub_props(profile, profile_menu);
  if (registration) {
    auto properties = ibus_prop_list_new();
    ibus_prop_list_append(properties, toolbar);
    ibus_prop_list_append(properties, desktop_tools_property(engine));
    ibus_prop_list_append(properties, candidate_actions(engine));
    ibus_prop_list_append(properties, property);
    ibus_prop_list_append(properties, voice);
    ibus_prop_list_append(properties, voice_cancel_property);
    ibus_prop_list_append(properties, cloud);
    ibus_prop_list_append(properties, translations);
    ibus_prop_list_append(properties, translation_language);
    ibus_prop_list_append(properties, punctuation);
    ibus_prop_list_append(properties, smart_punctuation);
    ibus_prop_list_append(properties, smart_repeat);
    ibus_prop_list_append(properties, paired);
    ibus_prop_list_append(properties, punctuation_lock);
    ibus_prop_list_append(properties, character_mode);
    ibus_prop_list_append(properties, traditional);
    ibus_prop_list_append(properties, english);
    ibus_prop_list_append(properties, english_mode);
    ibus_prop_list_append(properties, autocorrect_transposition_property);
    ibus_prop_list_append(properties, autocorrect_neighbor_property);
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
    ibus_prop_list_append(properties, word_character_property);
    ibus_prop_list_append(properties, preedit_property);
    ibus_prop_list_append(properties, theme_property);
    ibus_prop_list_append(properties, skin_property);
    ibus_prop_list_append(properties, scheme);
    ibus_prop_list_append(properties, profile);
    ibus_prop_list_append(properties, local_modes_property);
    ibus_engine_register_properties(engine, properties);
  } else {
    ibus_engine_update_property(engine, toolbar);
    ibus_engine_update_property(engine, desktop_tools_property(engine));
    ibus_engine_update_property(engine, candidate_actions(engine));
    ibus_engine_update_property(engine, property);
    ibus_engine_update_property(engine, voice);
    ibus_engine_update_property(engine, voice_cancel_property);
    ibus_engine_update_property(engine, cloud);
    ibus_engine_update_property(engine, translations);
    ibus_engine_update_property(engine, translation_language);
    ibus_engine_update_property(engine, punctuation);
    ibus_engine_update_property(engine, smart_punctuation);
    ibus_engine_update_property(engine, smart_repeat);
    ibus_engine_update_property(engine, paired);
    ibus_engine_update_property(engine, punctuation_lock);
    ibus_engine_update_property(engine, character_mode);
    ibus_engine_update_property(engine, traditional);
    ibus_engine_update_property(engine, english);
    ibus_engine_update_property(engine, english_mode);
    ibus_engine_update_property(engine, autocorrect_transposition_property);
    ibus_engine_update_property(engine, autocorrect_neighbor_property);
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
    ibus_engine_update_property(engine, word_character_property);
    ibus_engine_update_property(engine, preedit_property);
    ibus_engine_update_property(engine, theme_property);
    ibus_engine_update_property(engine, skin_property);
    ibus_engine_update_property(engine, scheme);
    ibus_engine_update_property(engine, profile);
    ibus_engine_update_property(engine, local_modes_property);
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
  if (!*global_input_enabled && s.voice_active)
    voice_cancel(engine);
  s.invalidate_providers();
  if (!*global_input_enabled && s.session)
    apply(engine, msime_client_command(s.session, MSIME_COMMIT_RAW));
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
        ibus_text_new_from_static_string("在中文方案中补充表达候选"), !menu_save_pending, TRUE,
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
  if (state(engine).voice_active) {
    auto &s = state(engine);
    ibus_engine_update_preedit_text_with_mode(
        engine,
        ibus_text_new_from_string(s.voice_preedit.c_str()),
        static_cast<guint>(g_utf8_strlen(s.voice_preedit.c_str(), -1)),
        !s.voice_preedit.empty(), IBUS_ENGINE_PREEDIT_CLEAR);
    ibus_engine_hide_lookup_table(engine);
    s.wave_overlay.status = s.voice_phase;
    s.wave_overlay.locked = s.voice_space_locked && !s.voice_stopping;
    s.wave_overlay.listening = !s.voice_stopping && s.voice_level.has_value();
    if (s.wave_overlay_surface) {
      if (s.wave_overlay_visible)
        s.wave_overlay_surface->update(s.wave_overlay);
      else
        s.wave_overlay_visible = s.wave_overlay_surface->show(s.wave_overlay);
    }
    return;
  }
  if (state(engine).wave_overlay_surface && state(engine).wave_overlay_visible) {
    state(engine).wave_overlay_surface->hide();
    state(engine).wave_overlay_visible = false;
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
    if (candidate.value("corrected", false))
      value += "*";
    if (state(engine).candidate_translations && !state(engine).translation_reset_pending &&
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
    auto label_text = ibus_text_new_from_string(label.c_str());
    if (state(engine).candidate_number_color)
      ibus_text_append_attribute(label_text, IBUS_ATTR_TYPE_FOREGROUND,
                                 *state(engine).candidate_number_color, 0, G_MAXUINT);
    ibus_lookup_table_append_label(table, label_text);
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
    if (!text.empty()) {
      commit_text(engine, text);
    }
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
  uint64_t focus_epoch;
  std::string text;
  bool final = true;
  unsigned level = 0;
  bool provider_failed = false;
  bool inline_preedit = false;
};
struct VoiceStreamContext {
  MsimeVoiceWorker::Progress progress;
  std::function<void(uint8_t)> status;
  std::function<void(float)> level;
};
extern "C" void voice_provider_level_update(float level, void *context) {
  auto *stream = static_cast<VoiceStreamContext *>(context);
  try {
    if (stream && stream->level && level >= 0.0f && level <= 1.0f) stream->level(level);
  } catch (...) {}
}
extern "C" void voice_provider_status_update(uint8_t phase, void *context) {
  auto *stream = static_cast<VoiceStreamContext *>(context);
  try {
    if (stream && stream->status && phase <= 2) stream->status(phase);
  } catch (...) {}
}
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
      "capture_backend", "capture_device", "commit_mode", "asr_provider", "asr_model", "asr_resource_id",
      "polish_provider", "polish_model", "doubao_boosting_table_id",
      "polish_prompt_id"};
  for (const auto *key : string_keys) {
    if (!voice.contains(key) || !voice.at(key).is_string())
      continue;
    auto value = voice.at(key).get<std::string>();
    if (value.size() > 512) {
      size_t end = 512;
      while (end && (static_cast<unsigned char>(value[end]) & 0xc0) == 0x80) --end;
      value.resize(end);
    }
    options[key] = std::move(value);
  }
  const auto preset = voice.value("polish_prompt_id", std::string{"cleanup"});
  const char *prompt_key = nullptr;
  if (preset == "custom" || preset == "custom_1") prompt_key = "polish_prompt_custom_1";
  else if (preset == "custom_2") prompt_key = "polish_prompt_custom_2";
  else if (preset == "custom_3") prompt_key = "polish_prompt_custom_3";
  if (prompt_key) {
    auto prompt = voice.value(prompt_key, std::string{});
    if (prompt.empty() && std::string(prompt_key) == "polish_prompt_custom_1")
      prompt = voice.value("polish_prompt", std::string{});
    if (prompt.size() > 8192) throw std::runtime_error("Voice prompt exceeds limit");
    if (!prompt.empty()) options[prompt_key] = std::move(prompt);
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
  s.voice_stopping = false;
  s.voice_phase = "正在录音…";
  s.voice_level.reset();
  s.wave_overlay = {};
  s.wave_overlay.actions_visible = false;
  if (s.wave_overlay_surface && s.wave_overlay_visible)
    s.wave_overlay_surface->hide();
  s.wave_overlay_visible = false;
  s.voice_generation = 0;
  s.voice_preedit.clear();
  s.voice_transcript.clear();
  s.wave_overlay.transcript.clear();
  s.voice_space_locked = false;
  s.voice_worker.cancel_async();
  if (s.session)
    render(engine, s.view);
  publish_mode(engine);
}
void voice_stop(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.voice_active || s.voice_stopping || s.voice_provider_socket.empty())
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
  if (!stopped) {
    voice_cancel(engine);
    ibus_engine_update_auxiliary_text(engine,
        ibus_text_new_from_static_string(
            "结束录音失败，本次语音已取消，请检查语音服务后重试"), TRUE);
  } else {
    s.voice_stopping = true;
    s.voice_phase = "正在识别…";
    render(engine, s.view);
    s.voice_space_locked = false;
    publish_mode(engine);
  }
}
void voice_start_impl(IBusEngine *engine) {
  auto &s = state(engine);
  if (!s.voice_enabled || s.voice_provider_socket.empty() || !s.session ||
      !s.focused || s.blocked || !s.input_enabled || s.voice_active)
    return;
  const auto provider_options = voice_provider_options(
      configured.value("preferences", Json::object()));
  const auto editing_text =
      s.view.value("editing_text", std::string{});
  const auto candidates = s.view.value("candidates", Json::array());
  if (!editing_text.empty() ||
      (candidates.is_array() && !candidates.empty()))
    apply(engine, msime_client_command(s.session, MSIME_CANCEL));
  const auto started = response(msime_client_voice_start(s.session));
  const auto generation = started.get<uint64_t>();
  const auto focus_epoch = s.focus_epoch;
  s.voice_active = true;
  s.voice_phase = "正在录音…";
  s.voice_level.reset();
  s.wave_overlay = {};
  s.wave_overlay.listening = true;
  s.wave_overlay.actions_visible = true;
  s.wave_overlay_visible = false;
  s.voice_stopping = false;
  s.voice_generation = generation;
  s.voice_space_locked = false;
  const auto socket = s.voice_provider_socket;
  const auto language = s.voice_language;
  const bool stream_inline_preedit = msime_voice_stream_inline_enabled(
      provider_options.value("stream_inline_preedit", false),
      provider_options.value("asr_provider", std::string{"doubao"}));
  const auto alive = s.alive;
  const auto provider_succeeded = std::make_shared<std::atomic_bool>(false);
  s.voice_worker.run_stream(
      [socket, language, generation, focus_epoch, engine, alive, provider_succeeded,
       provider_options](const std::atomic_bool &cancelled,
                         const MsimeVoiceWorker::Progress &progress) {
        if (cancelled.load())
          return std::string{};
        const auto query = Json{{"language", language},
                                {"generation", generation},
                                {"options", provider_options}}
                               .dump();
        VoiceStreamContext stream{progress, [engine, alive, generation, focus_epoch, &cancelled](uint8_t phase) {
          if (cancelled.load()) return;
          const char *labels[] = {"正在录音…", "正在识别…", "正在润色…"};
          auto *result = new VoiceResult{engine, alive, generation, focus_epoch, labels[phase], false};
          g_idle_add_full(G_PRIORITY_DEFAULT, +[](gpointer data) -> gboolean {
            std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
            if (!result->alive->load()) return G_SOURCE_REMOVE;
            auto &s = state(result->engine);
            if (!s.voice_active || s.voice_generation != result->generation ||
                s.focus_epoch != result->focus_epoch ||
                !s.session || !s.focused || s.blocked || !s.input_enabled)
              return G_SOURCE_REMOVE;
            if (s.voice_stopping && result->text == "正在录音…") return G_SOURCE_REMOVE;
            s.voice_phase = std::move(result->text);
            if (s.voice_phase == "正在录音…")
              s.wave_overlay.compact_status = msime::linux_host::WaveOverlayModel::CompactStatus::None;
            else if (s.voice_phase.find("识别") != std::string::npos)
              s.wave_overlay.compact_status = msime::linux_host::WaveOverlayModel::CompactStatus::Recognizing;
            else
              s.wave_overlay.compact_status = msime::linux_host::WaveOverlayModel::CompactStatus::Processing;
            if (s.voice_phase != "正在录音…") s.voice_stopping = true;
            render(result->engine, s.view);
            publish_mode(result->engine);
            return G_SOURCE_REMOVE;
          }, result, nullptr);
        }, [engine, alive, generation, focus_epoch, &cancelled](float level) {
          if (cancelled.load()) return;
          auto *result = new VoiceResult{engine, alive, generation, focus_epoch, {}, false,
              static_cast<unsigned>(level * 10.0f + 0.5f)};
          g_idle_add_full(G_PRIORITY_DEFAULT, +[](gpointer data) -> gboolean {
            std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
            if (!result->alive->load()) return G_SOURCE_REMOVE;
            auto &s = state(result->engine);
            if (!s.voice_active || s.voice_stopping || s.voice_generation != result->generation ||
                s.focus_epoch != result->focus_epoch ||
                !s.session || !s.focused || s.blocked || !s.input_enabled)
              return G_SOURCE_REMOVE;
            if (s.voice_level != result->level) {
              s.voice_level = result->level;
              s.wave_overlay.listening = true;
              s.wave_overlay.set_input_level(result->level / 10.0f);
              render(result->engine, s.view);
            }
            return G_SOURCE_REMOVE;
          }, result, nullptr);
        }};
        auto *raw = msime_client_voice_provider_stream_feedback(
            reinterpret_cast<const uint8_t *>(query.data()), query.size(),
            reinterpret_cast<const uint8_t *>(socket.data()), socket.size(),
            voice_provider_stream_update, voice_provider_status_update, voice_provider_level_update, &stream);
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
          auto text = msime_voice_bound_result(value.value("text", std::string{}));
          provider_succeeded->store(true);
          return text;
        } catch (...) {
          return std::string{};
        }
      },
      [engine, alive, generation, focus_epoch,
       stream_inline_preedit](std::string text, bool final) {
        if (final || text.empty())
          return;
        auto *result = new VoiceResult{engine, alive, generation, focus_epoch,
                                       std::move(text), false};
        result->inline_preedit = stream_inline_preedit;
        g_idle_add_full(
            G_PRIORITY_DEFAULT,
            +[](gpointer data) -> gboolean {
              std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
              if (!result->alive->load())
                return G_SOURCE_REMOVE;
              auto &s = state(result->engine);
              if (!s.voice_active || s.voice_generation != result->generation ||
                s.focus_epoch != result->focus_epoch ||
                  !s.session || !s.focused || s.blocked || !s.input_enabled)
                return G_SOURCE_REMOVE;
              auto text = msime_voice_bound_result(std::move(result->text));
              if (result->inline_preedit) {
                s.voice_preedit = std::move(text);
                s.voice_transcript.clear();
                s.wave_overlay.transcript.clear();
              } else {
                s.voice_transcript = std::move(text);
                s.wave_overlay.set_transcript(s.voice_transcript);
                s.voice_preedit.clear();
              }
              render(result->engine, s.view);
              return G_SOURCE_REMOVE;
            },
            result, nullptr);
      },
      [engine, alive, generation, focus_epoch, provider_succeeded](std::string text) {
        auto *result = new VoiceResult{engine, alive, generation, focus_epoch, std::move(text),
                                       true, 0, !provider_succeeded->load()};
        g_idle_add_full(
            G_PRIORITY_DEFAULT,
            +[](gpointer data) -> gboolean {
              std::unique_ptr<VoiceResult> result(static_cast<VoiceResult *>(data));
              if (!result->alive->load())
                return G_SOURCE_REMOVE;
              auto &s = state(result->engine);
              if (!s.voice_active || s.voice_generation != result->generation ||
                s.focus_epoch != result->focus_epoch ||
                  !s.session || !s.focused || s.blocked || !s.input_enabled) {
                return G_SOURCE_REMOVE;
              }
              try {
                if (result->text.empty()) {
                  msime_client_string_free(msime_client_voice_cancel(s.session));
                  s.voice_active = false;
                  s.voice_generation = 0;
                  s.voice_preedit.clear();
                  s.voice_transcript.clear();
                  s.wave_overlay.transcript.clear();
                  s.voice_space_locked = false;
                  render(result->engine, s.view);
                  publish_mode(result->engine);
                  ibus_engine_update_auxiliary_text(result->engine,
                      ibus_text_new_from_static_string(result->provider_failed
                          ? "语音输入失败，请检查语音服务、麦克风及提供商配置后重试"
                          : "未识别到文字，请重新录音"), TRUE);
                  return G_SOURCE_REMOVE;
                }
                auto applied = response(msime_client_voice_apply(
                    s.session, result->generation,
                    reinterpret_cast<const uint8_t *>(result->text.data()),
                    result->text.size()));
                s.voice_active = false;
                s.voice_generation = 0;
                s.voice_preedit.clear();
                s.voice_transcript.clear();
                s.wave_overlay.transcript.clear();
                s.voice_space_locked = false;
                if (applied.is_string()) {
                  auto text = traditional_display(
                      s, Json{{"scheme", s.view.value("scheme", 0)},
                              {"local_mode", "none"}},
                      applied.get<std::string>());
                  if (s.fullwidth)
                    text = fullwidth_text(std::move(text));
                  commit_text(result->engine, text);
                }
                render(result->engine, s.view);
                publish_mode(result->engine);
              } catch (...) {
                s.voice_active = false;
                s.voice_generation = 0;
                s.voice_preedit.clear();
                s.voice_transcript.clear();
                s.wave_overlay.transcript.clear();
                s.voice_space_locked = false;
                msime_client_string_free(msime_client_voice_cancel(s.session));
                render(result->engine, s.view);
                publish_mode(result->engine);
                ibus_engine_update_auxiliary_text(result->engine,
                    ibus_text_new_from_static_string("语音结果处理失败，请重新录音"), TRUE);
              }
              return G_SOURCE_REMOVE;
            },
            result, nullptr);
      });
  render(engine, s.view);
  publish_mode(engine);
}
void voice_start(IBusEngine *engine) {
  try {
    voice_start_impl(engine);
  } catch (...) {
    // Configuration and Host API errors may contain private values. Only
    // show a fixed message after dropping any partially started generation.
    voice_cancel(engine);
    ibus_engine_update_auxiliary_text(engine,
        ibus_text_new_from_static_string(
            "无法启动语音输入，请检查语音设置后重试"), TRUE);
  }
}
bool voice_hotkey(const State &s, guint key, guint modifiers) {
  if (key == IBUS_F9 && modifiers == IBUS_CONTROL_MASK)
    return s.voice_hotkey_ctrl_f9;
  if (key == IBUS_Alt_R && modifiers == (IBUS_MOD1_MASK | IBUS_CONTROL_MASK))
    return s.voice_hotkey_rctrl_ralt && s.right_ctrl_down;
  if (key == IBUS_Alt_R && modifiers == IBUS_MOD1_MASK)
    return s.voice_hotkey_ralt;
  if ((key == IBUS_Super_L || key == IBUS_Super_R) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_MOD4_MASK))
    return s.voice_hotkey_ctrl_win;
  return false;
}
void set_surrounding(IBusEngine *engine, IBusText *text, guint cursor, guint anchor) {
  // Keep platform context available without feeding it into Engine composition.
  auto &s = state(engine);
  s.surrounding_text = text && ibus_text_get_text(text) ? ibus_text_get_text(text) : "";
  s.surrounding_cursor = cursor;
  s.surrounding_anchor = anchor;
}
void focus_in(IBusEngine *engine) {
  guarded(engine, "focus_in", [&] {
    auto &s = state(engine);
    const bool already_focused = s.focused;
    const auto previous_session = s.session;
    s.focused = true;
    ++s.focus_epoch;
    ibus_engine_get_surrounding_text(engine, nullptr, nullptr, nullptr);
    // Host shortcuts and presentation also apply before a runtime is needed.
    s.refresh_host_preferences(configured.at("preferences"));
    s.open();
    s.key_router.set_lease({s.client_token, s.focus_epoch, s.session});
    watch_clipboard_history(engine);
    sync_global_input_mode(engine);
    // IBus may replay focus after negotiating client identity. Re-focusing
    // the same runtime would cancel input already typed during negotiation.
    if (s.session && (!already_focused || s.session != previous_session))
      apply(engine, msime_client_focus(s.session, s.input_enabled));
    if (!s.properties_registered &&
        g_getenv("MSIME_DISABLE_IBUS_PROPERTIES") == nullptr) {
      register_properties(engine);
      s.properties_registered = true;
    } else if (s.properties_registered &&
               (!already_focused || s.session != previous_session)) {
      // FocusOut disabled the existing menu. Refresh its state on activation
      // without re-registering it or disturbing repeated focus negotiation.
      publish_mode(engine);
    }
  });
}
void focus_out(IBusEngine *engine) {
  guarded(engine, "focus_out", [&] {
    auto &s = state(engine);
    voice_cancel(engine);
    s.key_router.cancel({s.client_token, s.focus_epoch, s.session});
    s.voice_consumed_keys.clear();
    s.voice_hold_key = 0;
    s.voice_space_consumed = false;
    s.focused = false;
    ++s.focus_epoch;
    s.focused_context.clear();
    s.surrounding_utf16 = false;
    s.stop_clipboard_monitor();
    s.native_compose.reset();
    s.reset_mode_modifiers();
    s.ai_context.clear();
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
  if (candidate_name == "InputEnabled" || candidate_name == "ChinesePunctuation" ||
      candidate_name == "CharacterWidth") {
    const char *target = candidate_name == "InputEnabled" ? "InputMode"
        : candidate_name == "ChinesePunctuation" ? "Punctuation" : "CharacterMode";
    property_activate(engine, target, value);
    return;
  }
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
  if (property_name == "VoiceCancel") {
    if (s.focused && !s.blocked && s.input_enabled && s.session && s.voice_active)
      guarded(engine, "voice_menu_cancel", [&] { voice_cancel(engine); });
    return;
  }
  if (property_name == "ClipboardHistory/OpenPanel") {
    if (s.focused && !s.blocked && !launch_desktop_panel("clipboard"))
      g_warning("Cannot start MSIME clipboard panel launcher");
    return;
  }
  if (property_name.rfind("DesktopTools/", 0) == 0) {
    if (!s.focused || s.blocked)
      return;
    if (property_name == "DesktopTools/VoiceEnabled") {
      if (menu_save_pending || !s.focused || s.blocked) return;
      save_menu_preference(engine, MenuPreference::VoiceEnabled, value == PROP_STATE_CHECKED);
      return;
    }
    if (property_name == "DesktopTools/RetrySave") {
      if (!menu_save_pending && failed_menu_save &&
          failed_menu_save->configuration == configuration_generation &&
          failed_menu_save->directory == configured.value("preferences_directory", std::string{})) {
        const auto retry = *failed_menu_save;
        save_menu_preference(engine, retry.preference, retry.value);
      }
      return;
    }
    if (property_name == "DesktopTools/ToolbarEnabled") {
      if (value == PROP_STATE_CHECKED || value == PROP_STATE_UNCHECKED)
        save_menu_preference(engine, MenuPreference::Toolbar, value == PROP_STATE_CHECKED);
      return;
    }
    for (const auto &action : desktop_panel_actions) {
      if (property_name == action.property) {
        if (!launch_desktop_panel(action.panel))
          g_warning("Cannot start MSIME desktop panel launcher");
        return;
      }
    }
    return;
  }
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
                               property_name != "ClipboardHistory/Refresh" &&
                               property_name != "ClipboardHistory/Latest" &&
                               property_name != "ClipboardHistory/Clear" &&
                               property_name.rfind("ClipboardHistory/Remove/", 0) != 0;
  const bool clipboard_remove = property_name.rfind("ClipboardHistory/Remove/", 0) == 0;
  if (!name ||
       (!(clipboard_item || clipboard_remove) && property_name != "ClipboardHistory/Clear" &&
       property_name != "ClipboardHistory/Refresh" &&
       std::string(name) != "InputMode" &&
       std::string(name) != "ClipboardHistory/Enabled" &&
       std::string(name) != "VoiceInput" &&
       std::string(name) != "CloudCandidates" &&
       std::string(name) != "CandidateTranslations" &&
       property_name.rfind("TranslationLanguage/", 0) != 0 &&
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
       std::string(name) != "AutocorrectTransposition" &&
       std::string(name) != "AutocorrectNeighbor" &&
       std::string(name) != "Helpcode" &&
       property_name.rfind("HelpcodeSchema/", 0) != 0 &&
       std::string(name) != "EmojiCandidates" &&
       std::string(name) != "KaomojiCandidates" &&
       std::string(name) != "CandidateLayout/Vertical" &&
       std::string(name) != "CandidateLayout/Horizontal" &&
       property_name.rfind("CandidateSkin/", 0) != 0 &&
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
    if (property_name == "ClipboardHistory/Enabled") {
      if (menu_save_pending || !s.focused || s.blocked) return;
      save_menu_preference(engine, MenuPreference::ClipboardHistoryEnabled, value == PROP_STATE_CHECKED);
      publish_mode(engine);
      return;
    }
    if (property_name.rfind("ClipboardHistory/", 0) == 0 &&
        (!s.clipboard_enabled || !s.input_enabled))
      return;
    if (property_name == "VoiceInput") {
      if (!s.voice_enabled || s.voice_provider_socket.empty() || !s.session ||
          !s.input_enabled)
        return;
      if (value == PROP_STATE_CHECKED)
        voice_start(engine);
      else if (s.voice_active)
        voice_stop(engine);
      return;
    }
    if (property_name == "CloudCandidates") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (menu_save_pending || enabled == s.cloud_candidates)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CloudCandidates, enabled);
        return;
      }
      s.cloud_candidates_override = enabled;
      s.cloud_candidates = enabled;
      s.invalidate_providers();
      publish_mode(engine);
      if (enabled) online_schedule(engine);
      return;
    }
    if (property_name == "CandidateTranslations") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (menu_save_pending || enabled == s.candidate_translations)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CandidateTranslations, enabled);
        return;
      }
      s.candidate_translations_override = enabled;
      s.candidate_translations = enabled;
      s.invalidate_providers();
      sync_translation_preferences(engine);
      clear_candidate_translations(engine);
      publish_mode(engine);
      if (enabled)
        translation_schedule(engine);
      return;
    }
    if (property_name.rfind("TranslationLanguage/", 0) == 0) {
      if (value != PROP_STATE_CHECKED || menu_save_pending)
        return;
      const auto selected = property_name.substr(
          std::string("TranslationLanguage/").size());
      if (selected != "en" && selected != "fr" && selected != "ja" &&
          selected != "es" && selected != "ru" && selected != "de" &&
          selected != "ko")
        return;
      if (selected == s.translation_target_language)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::TranslationLanguage, selected);
        return;
      }
      s.translation_target_language_override = selected;
      s.translation_target_language = selected;
      s.invalidate_providers();
      sync_translation_preferences(engine);
      clear_candidate_translations(engine);
      publish_mode(engine);
      if (s.candidate_translations)
        translation_schedule(engine);
      return;
    }
    if (property_name == "NumberRowSelection") {
      if (s.view.value("nine_key", false) || menu_save_pending ||
          s.number_row_selection == (value == PROP_STATE_CHECKED))
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::NumberRowSelection, value == PROP_STATE_CHECKED);
        return;
      }
      s.number_row_selection = value == PROP_STATE_CHECKED;
      s.number_row_override = s.number_row_selection;
      publish_mode(engine);
      return;
    }
    if (property_name == "NineKey") {
      const bool enabled = value == PROP_STATE_CHECKED;
      const auto active_scheme = s.scheme_override.value_or(
          configured.at("preferences").value("scheme", "quanpin"));
      if (menu_save_pending || active_scheme != "quanpin" ||
          s.view.value("nine_key", false) == enabled)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::NineKey, enabled);
        return;
      }
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
      if (menu_save_pending) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::LocalMode,
                             Json{{"key", key}, {"enabled", enabled}});
        return;
      }
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
      if (menu_save_pending || s.word_character_override.value_or(s.word_character.enabled) == enabled)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::WordCharacter, enabled);
        return;
      }
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
      if (menu_save_pending || value != PROP_STATE_CHECKED) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, active_scheme == "quanpin" ? MenuPreference::QuanpinHelpcodeSchema
                                                                : MenuPreference::ShuangpinHelpcodeSchema, selected);
        return;
      }
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
      if (value != PROP_STATE_CHECKED || menu_save_pending) return;
      const auto selected = property_name.substr(std::string("FrequencyMode/").size());
      if (selected != "disabled" && selected != "pin" && selected != "halve" &&
          selected != "linear" && selected != "promote")
        return;
      if (s.frequency_mode_override.value_or(
              configured.at("preferences").value("frequency", Json::object())
                  .value("mode", "promote")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::FrequencyMode, selected);
        return;
      }
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
        if (value != PROP_STATE_CHECKED || menu_save_pending) return;
        const auto suffix = property_name.substr(std::string("CandidatePageSize/").size());
        if (suffix.size() != 1 || suffix.front() < '1' || suffix.front() > '9') return;
        const auto selected = static_cast<uint8_t>(suffix.front() - '0');
        if (s.candidate_page_size_override.value_or(
                configured.at("preferences").value("candidate_page_size", 5)) == selected)
          return;
        const auto directory = configured.value("preferences_directory", std::string{});
        if (!directory.empty() && directory.front() == '/') {
          save_menu_preference(engine, MenuPreference::CandidatePageSize, selected);
          return;
        }
        if (!s.session) return;
        s.candidate_page_size_override = static_cast<uint8_t>(selected);
        s.view = response(msime_client_set_candidate_page_size(
                         s.session, static_cast<uint8_t>(selected))).at("view");
        render(engine, s.view);
        publish_mode(engine);
      } catch (...) {
      }
      return;
    }
    if (property_name.rfind("ShuangpinProfile/", 0) == 0) {
      if (value != PROP_STATE_CHECKED || menu_save_pending) return;
      const auto selected = property_name.substr(std::string("ShuangpinProfile/").size());
      if (selected != "xiaohe" && selected != "ziranma" && selected != "shoudao" &&
          selected != "microsoft")
        return;
      if (s.shuangpin_profile_override.value_or(
              configured.at("preferences").value("shuangpin_profile", "xiaohe")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::ShuangpinProfile, selected);
        return;
      }
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
    if (property_name == "ClipboardHistory/Refresh") {
      if (!s.input_enabled || s.clipboard_history_path.empty())
        return;
      ++s.clipboard_generation;
      s.clipboard_items_cache.clear();
      s.clipboard_loaded = false;
      publish_mode(engine);
      return;
    }
    if (clipboard_remove || clipboard_item) {
      for (size_t index = 0; index < s.clipboard_items_cache.size(); ++index) {
        const auto expected = std::string(clipboard_remove
            ? "ClipboardHistory/Remove/" : "ClipboardHistory/") +
            std::to_string(s.clipboard_generation) + "/" + std::to_string(index);
        if (property_name != expected)
          continue;
        const auto text = s.clipboard_items_cache[index];
        if (clipboard_remove) {
          if (clipboard_delete(s.clipboard_history_path, text)) {
            s.clipboard_items_cache.clear();
            s.clipboard_loaded = false;
            ++s.clipboard_generation;
            publish_mode(engine);
          }
        } else {
          commit_text(engine, text);
        }
        return;
      }
      return;
    }
    if (property_name == "ClipboardHistory/Clear") {
      if (!clipboard_delete(s.clipboard_history_path, std::nullopt))
        return;
      s.clipboard_items_cache.clear();
      s.clipboard_loaded = false;
      ++s.clipboard_generation;
      publish_mode(engine);
      return;
    }
    if (property_name == "PairedPunctuation") {
      if (menu_save_pending || (value == PROP_STATE_CHECKED) == s.paired_punctuation) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::PairedPunctuation, value == PROP_STATE_CHECKED);
        return;
      }
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.session) {
        s.view = response(msime_client_set_paired_punctuation(s.session, enabled));
        render(engine, s.view);
      }
      s.paired_punctuation_override = enabled;
      s.paired_punctuation = enabled;
      s.last_smart_punctuation = 0;
      s.smart_punctuation_rejected = 0;
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuation") {
      if (menu_save_pending || (value == PROP_STATE_CHECKED) == s.smart_punctuation) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::SmartPunctuation, value == PROP_STATE_CHECKED);
        return;
      }
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
      if (menu_save_pending || (value == PROP_STATE_CHECKED) == s.smart_punctuation_repeat) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::SmartPunctuationRepeat, value == PROP_STATE_CHECKED);
        return;
      }
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
      if (menu_save_pending || s.fullwidth == (value == PROP_STATE_CHECKED)) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CharacterWidth, value == PROP_STATE_CHECKED);
        return;
      }
      s.fullwidth = value == PROP_STATE_CHECKED;
      if (s.session) {
        s.view = response(msime_client_set_character_width(s.session, s.fullwidth));
        render(engine, s.view);
      }
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "TraditionalOutput") {
      if (s.scheme_override.value_or(
              configured.at("preferences").value("scheme", "quanpin")) ==
          "japanese")
        return;
      if (menu_save_pending || s.traditional_output == (value == PROP_STATE_CHECKED)) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::TraditionalOutput, value == PROP_STATE_CHECKED);
        return;
      }
      s.traditional_output = value == PROP_STATE_CHECKED;
      s.traditional_output_override = s.traditional_output;
      render(engine, s.view);
      publish_mode(engine);
      return;
    }
    if (std::string(name).rfind("CandidateTheme/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("CandidateTheme/").size());
      if (value != PROP_STATE_CHECKED || menu_save_pending)
        return;
      if (s.theme_override.value_or(
              configured.at("preferences").value("candidate_theme", "follow")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CandidateTheme, selected);
        return;
      }
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
      if (value != PROP_STATE_CHECKED || menu_save_pending)
        return;
      bool available = selected == "fluent" || selected == "wechat" ||
                       selected == "graphite" || selected == "willow_green";
      const auto catalog = configured.find("candidate_skin_catalog");
      if (!available && catalog != configured.end() && catalog->is_object()) {
        const auto packages = catalog->find("packages");
        if (packages != catalog->end() && packages->is_array()) {
          for (const auto &package : *packages) {
            if (package.is_object() && package.value("id", std::string{}) == selected) {
              available = true;
              break;
            }
          }
        }
      }
      if (!available) return;
      if (s.skin_override.value_or(
              configured.at("preferences").value("candidate_skin", "fluent")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CandidateSkin, selected);
        return;
      }
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
      if (value != PROP_STATE_CHECKED || menu_save_pending)
        return;
      if (s.preedit_override.value_or(
              configured.at("preferences").value("tsf_preedit_style", "raw")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::PreeditStyle, selected);
        return;
      }
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
      if (value != PROP_STATE_CHECKED || menu_save_pending)
        return;
      if (s.layout_override.value_or(
              configured.at("preferences").value("candidate_layout", "vertical")) == selected)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::CandidateLayout, selected);
        return;
      }
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
      if (menu_save_pending) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, std::string(name) == "EmojiCandidates" ? MenuPreference::EmojiCandidates : MenuPreference::KaomojiCandidates, enabled);
        return;
      }
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
      if (menu_save_pending) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::EnglishCandidates, enabled);
        return;
      }
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
    if (std::string(name) == "AutocorrectTransposition" ||
        std::string(name) == "AutocorrectNeighbor") {
      const bool enabled = value == PROP_STATE_CHECKED;
      const bool transposition = std::string(name) == "AutocorrectTransposition";
      const auto key = transposition ? "autocorrect_transposition" : "autocorrect_neighbor";
      const auto current = configured.at("preferences").value("quanpin", Json::object())
          .value(key, configured.at("preferences").value("autocorrect", true));
      auto &setting_override = transposition ? s.autocorrect_transposition_override
                                             : s.autocorrect_neighbor_override;
      if (menu_save_pending || setting_override.value_or(current) == enabled)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, transposition ? MenuPreference::AutocorrectTransposition
                                                  : MenuPreference::AutocorrectNeighbor, enabled);
        return;
      }
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
      if (menu_save_pending) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, active_scheme == "quanpin" ? MenuPreference::QuanpinHelpcode
                                                                : MenuPreference::ShuangpinHelpcode, enabled);
        return;
      }
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
      if (value != PROP_STATE_CHECKED || menu_save_pending) return;
      auto selected = property_name == "Scheme/Japanese" ? std::string("japanese")
          : property_name == "Scheme/Quanpin" ? std::string("quanpin")
          : property_name == "Scheme/Shuangpin" ? std::string("shuangpin")
          : property_name == "Scheme/Wubi" ? std::string("wubi")
          : configured.at("preferences").value("last_chinese_scheme", std::string("quanpin"));
      if (selected != "japanese" && selected != "quanpin" &&
          selected != "shuangpin" && selected != "wubi") selected = "quanpin";
      if (s.scheme_override.value_or(
              configured.at("preferences").value("scheme", "quanpin")) == selected) return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::InputScheme, selected);
        return;
      }
      // Scheme-specific session overrides must not leak into the newly
      // selected scheme. Shared preferences remain intact and are reloaded
      // by the recreated Engine session.
      s.helpcode_override.reset();
      s.helpcode_schema_override.reset();
      s.autocorrect_transposition_override.reset();
      s.autocorrect_neighbor_override.reset();
      s.nine_key_override.reset();
      s.shuangpin_profile_override.reset();
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.scheme_override = selected;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      publish_mode(engine);
      return;
    }
    const bool enabled = value == PROP_STATE_CHECKED;
    if (std::string(name).rfind("PunctuationLock/", 0) == 0) {
      const auto selected = std::string(name).substr(std::string("PunctuationLock/").size());
      if (value != PROP_STATE_CHECKED || menu_save_pending || selected == s.punctuation_lock)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::PunctuationLock, selected);
        return;
      }
      if (s.session) {
        s.view = response(msime_client_set_punctuation_lock(
            s.session, selected == "chinese" ? 1 : selected == "english" ? 2 : 0));
        render(engine, s.view);
      }
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
      if (!s.input_enabled || !s.session || menu_save_pending)
        return;
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::ChinesePunctuation, enabled);
        return;
      }
      s.view =
          response(msime_client_set_chinese_punctuation(s.session, enabled));
      s.chinese_punctuation = enabled;
      s.punctuation_override = enabled;
      publish_mode(engine);
      return;
    }
    if (enabled != s.input_enabled && !menu_save_pending) {
      const auto directory = configured.value("preferences_directory", std::string{});
      if (!directory.empty() && directory.front() == '/') {
        save_menu_preference(engine, MenuPreference::InputMode, enabled);
        return;
      }
      if (!enabled && s.voice_active)
        voice_cancel(engine);
      s.invalidate_providers();
      if (!enabled && s.session)
        apply(engine,
              msime_client_command(s.session, MSIME_COMMIT_RAW));
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
    state(engine).host_shortcut_strokes.clear();
    state(engine).ai_context.clear();
    state(engine).native_compose.reset();
    if (state(engine).voice_active)
      voice_cancel(engine);
    state(engine).voice_consumed_keys.clear();
    state(engine).voice_hold_key = 0;
    state(engine).voice_space_consumed = false;
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
    // IBus clients send evdev codes (GTK subtracts 8 from XKB hardware
    // codes). The number row is 2..11 (1..9,0); this preserves physical-key
    // selection when the active layout produces symbols such as '&' or 'é'.
    if (keycode >= 2 && keycode <= 11)
      return keycode == 11 ? 9 : static_cast<size_t>(keycode - 2);
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
  if (keycode >= 2 && keycode <= 11)
    return keycode == 11 ? 9 : static_cast<size_t>(keycode - 2);
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
  s.native_compose.reset();
  if (s.voice_active)
    voice_cancel(engine);
  s.invalidate_providers();
  // Windows mode switching commits the reading string, not the candidate.
  if (s.input_enabled && s.session)
    apply(engine, msime_client_command(s.session, MSIME_COMMIT_RAW));
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
  // A router lease cannot be issued before engine construction completes.
  if (s.client_token == 0)
    return FALSE;
  const msime_client_key_event routed_event = {{s.client_token, s.focus_epoch, s.session}, key, keycode,
      static_cast<uint32_t>(flags & (IBUS_SHIFT_MASK | IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)),
      key <= 0xffffu ? key : 0u, false};
  const auto dispatch_result = s.key_router.check(routed_event);
  if (dispatch_result != MSIME_CLIENT_KEY_SENT)
    return FALSE;
  const bool shift_key = key == IBUS_Shift_L || key == IBUS_Shift_R;
  const bool ctrl_key = key == IBUS_Control_L || key == IBUS_Control_R;
  const bool release = (flags & IBUS_RELEASE_MASK) != 0;
  // Physical key identity survives releasing Shift before the letter. Use a
  // normalized keysym only for synthetic events without a hardware keycode.
  const guint host_stroke = keycode != 0 ? keycode
      : ((key >= 'A' && key <= 'Z' ? key - 'A' + 'a' : key) | 0x80000000u);
  if (s.host_shortcut_strokes.count(host_stroke) != 0) {
    if (release) s.host_shortcut_strokes.erase(host_stroke);
    return TRUE;
  }
  // A held key can repeat after stop, cancellation or a fast final result.
  // Keep consuming its stroke even if modifiers or voice settings changed.
  if (!release &&
      (s.voice_consumed_keys.count(key) != 0 ||
       (key == IBUS_space && s.voice_space_consumed)))
    return TRUE;
  const bool repeated_modifier = !release &&
      ((shift_key && s.shift_down) || (ctrl_key && s.ctrl_down));
  if (shift_key) s.shift_down = !release;
  if (key == IBUS_Control_R) s.right_ctrl_down = !release;
  if (key == IBUS_Control_L) s.left_ctrl_down = !release;
  if (ctrl_key) s.ctrl_down = s.right_ctrl_down || s.left_ctrl_down;

  const guint chord_modifiers = flags &
      (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
       IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  if (shift_key && (flags & IBUS_RELEASE_MASK)) {
    if (!s.mode_shift_enabled || !s.pure_shift_candidate || chord_modifiers ||
        g_get_monotonic_time() >= s.modifier_toggle_deadline) {
      s.pure_shift_candidate = false;
      return FALSE;
    }
    s.pure_shift_candidate = false;
    if (!s.focused || s.blocked)
      return FALSE;
    guarded(engine, "process_key", [&] {
      toggle_input_mode(engine);
    });
    return TRUE;
  }
  if (shift_key && !(flags & IBUS_RELEASE_MASK)) {
    if (repeated_modifier) return FALSE;
    s.modifier_toggle_deadline = g_get_monotonic_time() + 500000;
    s.pure_ctrl_candidate = false;
    // A modifier already held when Shift arrives makes this a chord.
    // Ignore Caps/Num Lock; IBus includes Shift in the modifier mask for
    // the Shift key event itself.
    s.pure_shift_candidate =
        s.mode_shift_enabled && s.focused && !s.blocked && chord_modifiers == 0;
    return FALSE;
  }
  if (ctrl_key && (flags & IBUS_RELEASE_MASK)) {
    if (s.voice_requires_control && s.voice_hold_key &&
        (s.voice_hold_key == IBUS_Alt_R ? !s.right_ctrl_down : !s.ctrl_down)) {
      s.voice_hold_key = 0;
      s.voice_requires_control = false;
      s.pure_ctrl_candidate = false;
      if (s.voice_active && !s.voice_space_locked)
        guarded(engine, "voice_control_release", [&] { voice_stop(engine); });
      return FALSE;
    }
    if (!s.mode_ctrl_enabled || !s.pure_ctrl_candidate ||
        (chord_modifiers & ~IBUS_CONTROL_MASK) ||
        (flags & IBUS_SHIFT_MASK) ||
        g_get_monotonic_time() >= s.modifier_toggle_deadline) {
      s.pure_ctrl_candidate = false;
      return FALSE;
    }
    s.pure_ctrl_candidate = false;
    if (!s.focused || s.blocked)
      return FALSE;
    guarded(engine, "process_key", [&] { toggle_input_mode(engine); });
    return TRUE;
  }
  if (ctrl_key && !(flags & IBUS_RELEASE_MASK)) {
    if (repeated_modifier) return FALSE;
    s.modifier_toggle_deadline = g_get_monotonic_time() + 500000;
    s.pure_shift_candidate = false;
    s.pure_ctrl_candidate =
        s.mode_ctrl_enabled && s.focused && !s.blocked &&
        (chord_modifiers & ~IBUS_CONTROL_MASK) == 0 &&
        (flags & IBUS_SHIFT_MASK) == 0;
    return FALSE;
  }
  // Own the complete consumed Space stroke. Modifier release order and
  // preference changes must not reinterpret repeats as another shortcut.
  if (key == IBUS_space && s.mode_chord_held) {
    if (release) s.mode_chord_held = false;
    return TRUE;
  }
  if (flags & IBUS_RELEASE_MASK) {
    if (key == IBUS_space && s.voice_space_consumed) {
      s.voice_space_consumed = false;
      return TRUE;
    }
    if (s.voice_consumed_keys.erase(key) != 0) {
      if (s.voice_hold_key == key) {
        s.voice_hold_key = 0;
        s.voice_requires_control = false;
        if (s.voice_active && !s.voice_space_locked)
          guarded(engine, "voice_hotkey_release", [&] { voice_stop(engine); });
      }
      return TRUE;
    }
    return FALSE;
  }
  s.pure_shift_candidate = false;
  s.pure_ctrl_candidate = false;
  const guint modifiers = flags & (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK |
                                   IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
                                   IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  const bool screen_keyboard_key =
      (key == IBUS_k || key == IBUS_K) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD4_MASK);
  if (!release && screen_keyboard_key && s.focused && !s.blocked) {
    if (!launch_desktop_panel("keyboard")) return FALSE;
    s.host_shortcut_strokes.insert(host_stroke);
    return TRUE;
  }
  const bool maintenance_restart_key =
      (key == IBUS_r || key == IBUS_R) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD1_MASK);
  if (!release && maintenance_restart_key && s.focused && !s.blocked) {
    if (!restart_ibus_service()) return FALSE;
    s.host_shortcut_strokes.insert(host_stroke);
    return TRUE;
  }
  const bool maintenance_clear_cache_key =
      (key == IBUS_c || key == IBUS_C) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD1_MASK);
  if (!release && maintenance_clear_cache_key && s.focused && !s.blocked) {
    s.host_shortcut_strokes.insert(host_stroke);
    guarded(engine, "reset_engine_cache", [&] {
      s.open();
      if (s.session)
        apply(engine, msime_client_reset_cache(s.session));
    });
    return TRUE;
  }
  const bool maintenance_exit_key =
      (key == IBUS_t || key == IBUS_T) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD1_MASK);
  if (!release && maintenance_exit_key && s.focused && !s.blocked) {
    s.host_shortcut_strokes.insert(host_stroke);
    // Match the Windows maintenance shortcut: stop this user-owned IBus
    // preview process without touching another IBus daemon or input source.
    ibus_quit();
    return TRUE;
  }
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
  // Disabling IME spelling must not disable the system layout's Compose table.
  // GTK's asynchronous IBus passthrough does not perform dead-key composition.
  if (s.focused && !s.blocked && !s.input_enabled && !release) {
    if ((modifiers & ~(IBUS_SHIFT_MASK | IBUS_MOD5_MASK)) == 0) {
      if (const auto text = s.native_compose.feed(key)) {
        if (!text->empty()) commit_text(engine, *text);
        return TRUE;
      }
    } else {
      s.native_compose.reset();
    }
  }
  if (!s.focused || s.blocked || (!s.input_enabled && !mode_toggle && !fullwidth_toggle) ||
      (flags & IBUS_RELEASE_MASK))
    return FALSE;
  // Windows locks an active hold-to-record shortcut when Space is pressed.
  // IBus exposes the same interaction as key events; consume both halves of
  // the Space stroke so it cannot leak into the focused editor while voice
  // recognition is active. With the option disabled, Space follows the
  // regular editor/Engine path. Menu and Ctrl+F9 recordings have no held
  // shortcut, and recognition/polishing can no longer be locked. Use the
  // active hold captured on key-down: extra modifiers pressed afterwards
  // must not invalidate it. Releasing a required key clears voice_hold_key.
  if (s.voice_active && !s.voice_stopping && s.voice_hotkey_hold_space_lock &&
      key == IBUS_space && s.voice_hold_key != 0) {
    s.voice_space_consumed = true;
    if (!s.voice_space_locked) {
      guarded(engine, "voice_space_lock", [&] {
        s.voice_space_locked = true;
        render(engine, s.view);
        publish_mode(engine);
      });
    }
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
      if (s.session) {
        s.view = response(msime_client_set_character_width(s.session, s.fullwidth));
        render(engine, s.view);
      }
      publish_mode(engine);
    });
    return TRUE;
  }
  const bool maintenance_candidate_key =
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK | IBUS_MOD1_MASK) &&
      key >= IBUS_1 && key <= IBUS_8;
  if (maintenance_candidate_key) {
    const auto candidates = s.view.value("candidates", Json::array());
    const auto index = static_cast<size_t>(key - IBUS_1);
    if (!candidates.is_array() || index >= candidates.size())
      return FALSE;
    const auto &candidate = candidates.at(index);
    if (!candidate.is_object() || !candidate.contains("id"))
      return FALSE;
    const auto &id = candidate.at("id");
    if (!id.is_object() || id.value("session", uint64_t{0}) != s.session)
      return FALSE;
    guarded(engine, "remove_candidate_shortcut", [&] {
      apply(engine, msime_client_remove_candidate(
          s.session, id.at("generation").get<uint64_t>(),
          id.at("index").get<size_t>()));
    });
    return TRUE;
  }
  if (modifier(key) &&
      !(s.voice_enabled && !s.voice_provider_socket.empty() && voice_hotkey(s, key, modifiers)))
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
  const auto fullwidth_idle_commit = [&](guint value) {
    if (!s.fullwidth || value < 0x21 || value > 0x7e)
      return false;
    const auto editing_text = s.view.value("editing_text", std::string{});
    const auto candidates = s.view.value("candidates", Json::array());
    if (!editing_text.empty() || (candidates.is_array() && !candidates.empty()))
      return false;
    auto text = fullwidth_text(std::string(1, static_cast<char>(value)));
    commit_text(engine, text);
    return true;
  };
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
      if (ctrl_alt_space)
        s.mode_chord_held = true;
      toggle_input_mode(engine);
      handled = true;
      return;
    }
    if ((modifiers & ~(IBUS_SHIFT_MASK | IBUS_MOD5_MASK)) == 0) {
      if (const auto text = s.native_compose.feed(key)) {
        if (!s.view.value("editing_text", std::string{}).empty() ||
            !s.view.value("candidates", Json::array()).empty())
          apply(engine, msime_client_command(s.session, MSIME_COMMIT_RAW));
        if (!text->empty()) commit_text(engine, *text);
        handled = true;
        return;
      }
    } else {
      s.native_compose.reset();
    }
    if (!s.input_enabled)
      return;
    if (voice_hotkey(s, key, modifiers) && s.voice_enabled &&
        !s.voice_provider_socket.empty()) {
      // Windows keeps one active hold chord; another hold shortcut cannot
      // replace it. Ctrl+F9 has an independent consumed-key lifetime.
      if (key != IBUS_F9 && s.voice_hold_key != 0)
        return;
      s.voice_consumed_keys.insert(key);
      // Hold shortcuts start/continue recording; only a locked recording
      // turns their next press into Stop. Ctrl+F9 always toggles recording.
      if (s.voice_active) {
        if (key == IBUS_F9 || s.voice_space_locked)
          voice_stop(engine);
      } else {
        voice_start(engine);
      }
      // A hold chord may take over a recording started from the menu or
      // Ctrl+F9. Releasing its Ctrl must stop just like releasing Win/RAlt.
      if (key != IBUS_F9) {
        s.voice_hold_key = key;
        s.voice_requires_control = (modifiers & IBUS_CONTROL_MASK) != 0;
      }
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
    if (!s.view.at("candidates").empty()) {
      if (const auto touch_navigation =
              msime::linux_host::touch_keyboard_command(key)) {
        handled = apply(engine, msime_client_command(
                                   s.session, *touch_navigation));
        return;
      }
    }
    // Disabled navigation keys belong to the application, including when a
    // composition is active. Finalize that composition first so the editor
    // never receives a navigation key while stale preedit is still owned by
    // the IBus engine.
    if (msime::linux_host::navigation_key(key)) {
      const bool binding_enabled = s.navigation.command(
          key, (flags & IBUS_SHIFT_MASK) != 0).has_value();
      if (!binding_enabled &&
          (!s.view.at("editing_text").get<std::string>().empty() ||
           !s.view.at("candidates").empty()))
        apply(engine, msime_client_command(s.session, MSIME_COMMIT_CANDIDATE));
      return;
    }
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
    // AltGr selects layout text, not an application shortcut. Finish spelling
    // before forwarding it, without applying candidate or punctuation bindings.
    if ((modifiers & ~IBUS_SHIFT_MASK) == IBUS_MOD5_MASK &&
        g_unichar_isprint(ibus_keyval_to_unicode(key))) {
      apply(engine, msime_client_command(s.session, MSIME_COMMIT_RAW));
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
    const bool ordinary_candidate_digit =
        !s.english_mode && s.view.value("local_mode", "none") == "none" &&
        !s.view.value("nine_key", false) && !s.view.at("candidates").empty() &&
        ((key >= IBUS_0 && key <= IBUS_9) ||
         (key >= IBUS_KP_0 && key <= IBUS_KP_9));
    if (ordinary_candidate_digit &&
        (!s.number_row_selection || modifiers != 0)) {
      // The shared runtime's character action has a legacy numeric fallback
      // that selects candidates. Keep that fallback behind the Linux host
      // toggle, and never turn shifted digits into candidate selection.
      return;
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
          commit_text(engine, text);
          handled = true;
        }
      } else {
        // Arithmetic keypad marks keep the normal Engine punctuation policy
        // while remaining outside the configurable minus/equal paging keys.
        handled = apply(engine, msime_client_punctuation(
            s.session, static_cast<uint8_t>(*keypad)));
      }
      if (!handled)
        handled = fullwidth_idle_commit(static_cast<guint>(*keypad));
      return;
    }
    if (microsoft_shuangpin_ing_key(s.view, key, modifiers)) {
      handled = apply(engine, msime_client_character(s.session, ';', false));
      return;
    }
    if (unicode_plus_key(s.view, key, modifiers)) {
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
      if (!handled)
        handled = fullwidth_idle_commit(key);
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
        commit_text(engine, text);
        handled = true;
      }
      if (!handled)
        handled = fullwidth_idle_commit(key);
      if (handled)
        ibus_engine_forward_key_event(engine, IBUS_Left, 0, 0);
      return;
    }
    if (s.smart_punctuation_repeat && s.paired_punctuation && s.last_smart_punctuation == key &&
        s.last_smart_punctuation_time != 0 &&
        g_get_monotonic_time() - s.last_smart_punctuation_time <=
            kSmartPunctuationRepeatIntervalUs &&
        smart_punctuation_repeat_matches_document(s) &&
        s.view.at("editing_text").get<std::string>().empty()) {
      if (const auto *replacement = smart_punctuation_pair(static_cast<char>(key))) {
        ibus_engine_delete_surrounding_text(engine, -1, 1);
        // The preceding mark was replaced in the editor, not appended.
        if (!s.ai_context.empty()) {
          size_t last = s.ai_context.size() - 1;
          while (last > 0 &&
                 (static_cast<unsigned char>(s.ai_context[last]) & 0xc0) == 0x80)
            --last;
          s.ai_context.erase(last);
        }
        commit_text(engine, replacement);
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
        commit_text(engine, text);
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
      commit_text(engine, text);
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
                        ? lowercase_letter
                        : (local_mode != "none" || lowercase_letter ||
                           (uppercase_letter && (helpcode || s.english_mode)));
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
    const auto caret_position = s.view.value(
        "caret_position", s.view.value("editing_text", std::string{}).size());
    const bool accepted_apostrophe =
        key == IBUS_apostrophe && has_composition && caret_position != 0 &&
        ((local_mode == "none" && active_scheme != "wubi") ||
         local_mode == "emoji" || local_mode == "kaomoji" ||
         local_mode == "temporary_japanese");
    const bool candidate_input =
        candidate_active &&
        (accepted_letter || nine_key_digit || unicode_digit || microsoft_ing ||
         unicode_plus || accepted_apostrophe);
    if (candidate_input) {
      // Candidate visibility does not end composition. Engine owns how the
      // next spelling key extends the current input or local mode.
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
        const auto input_value =
            (flags & IBUS_SHIFT_MASK) && key >= 'a' && key <= 'z'
                ? key - 'a' + 'A'
                : key;
        handled = apply(engine, msime_client_character(
            s.session, static_cast<uint8_t>(input_value),
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
      if (!handled)
        handled = fullwidth_idle_commit(key);
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
      // Incremental candidates remain visible while Engine edits spelling.
      command = MSIME_BACKSPACE;
      break;
    case IBUS_Return:
    case IBUS_KP_Enter:
      command = MSIME_COMMIT_RAW;
      break;
    case IBUS_Escape:
      command = MSIME_CANCEL;
      break;
    case IBUS_space:
      if (s.fullwidth && !has_composition && !candidate_active) {
        commit_text(engine, "\xe3\x80\x80");
        handled = true;
        return;
      }
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
      command = MSIME_DELETE_FORWARD;
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
    else if (g_unichar_isprint(ibus_keyval_to_unicode(key)) &&
             (!s.view.value("editing_text", std::string{}).empty() ||
              !s.view.value("candidates", Json::array()).empty())) {
      // IBus keysyms may encode Unicode with a 0x01000000 prefix.
      // Windows finalizes the active TSF composition before handing an
      // unsupported printable key back to the application. Preserve the
      // same text while allowing IBus to deliver the original keyval.
      apply(engine, msime_client_command(s.session, MSIME_COMMIT_RAW));
      handled = false;
    } else
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
    if (!handled) {
      guint fullwidth_value = key;
      if (key >= IBUS_KP_0 && key <= IBUS_KP_9)
        fullwidth_value = '0' + key - IBUS_KP_0;
      handled = fullwidth_idle_commit(fullwidth_value);
    }
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
  uint64_t configuration_generation;
};
void apply_live_preferences(IBusEngine *engine, Json snapshot) {
  auto &s = state(engine);
  if (!s.focused || s.blocked)
    return;
  s.apply_session_overrides(snapshot);
  const auto &preferences = snapshot.at("preferences");
  if (!s.session) {
    if (preferences != s.applied_preferences_snapshot ||
        s.applied_display_generation != configuration_generation) {
      s.refresh_host_preferences(preferences);
      s.applied_preferences_snapshot = preferences;
      s.applied_display_generation = configuration_generation;
      publish_mode(engine);
    }
    sync_global_input_mode(engine);
    return;
  }
  if (preferences == s.applied_preferences_snapshot) {
    sync_global_input_mode(engine);
    if (s.applied_display_generation != configuration_generation) {
      s.refresh_host_preferences(preferences);
      render(engine, s.view);
      publish_mode(engine);
      s.applied_display_generation = configuration_generation;
    }
    return;
  }
  // Store revisions belong to the store. The runtime needs an increasing
  // revision for each effective change, including local menu overrides.
  snapshot["revision"] = s.applied_preferences_revision + 1;
  const auto encoded = snapshot.dump();
  auto updated = response(msime_client_update_preferences(
      s.session, reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
  ++s.applied_preferences_revision;
  if (s.applied_preferences_snapshot.is_object() &&
      s.applied_preferences_snapshot.value("ai_assistant", Json(nullptr)) !=
          preferences.value("ai_assistant", Json(nullptr))) {
    s.invalidate_providers();
    s.ai_context.clear();
  }
  if (s.applied_preferences_snapshot.is_object() &&
      s.applied_preferences_snapshot.value("custom_translation", Json(nullptr)) !=
          preferences.value("custom_translation", Json(nullptr))) {
    s.invalidate_providers();
    s.translation_reset_pending = true;
  }
  s.applied_preferences_snapshot = preferences;
  s.refresh_host_preferences(preferences);
  s.applied_display_generation = configuration_generation;
  // Subsequent mode synchronization or voice cancellation may replace this
  // view. Do not restore the pre-transition snapshot after those actions.
  s.view = updated.at("view");
  sync_global_input_mode(engine);
  if (s.voice_active && !s.voice_enabled)
    voice_cancel(engine);
  if (s.translation_reset_pending)
    clear_candidate_translations(engine);
  render(engine, s.view);
  publish_mode(engine);
  translation_schedule(engine);
  online_schedule(engine);
}
struct MenuPreferenceSave {
  std::string directory;
  uint64_t configuration;
  MenuPreference preference;
  Json value;
};
void save_menu_preference(IBusEngine *engine, MenuPreference preference, Json value) {
  const auto directory = configured.value("preferences_directory", std::string{});
  if (menu_save_pending || directory.empty() || directory.front() != '/')
    return;
  menu_save_pending = true;
  ++menu_status_generation;
  failed_menu_save.reset();
  publish_mode(engine);
  auto task = g_task_new(G_OBJECT(engine), nullptr,
      +[](GObject *source, GAsyncResult *result, gpointer) {
        menu_save_pending = false;
        ++menu_status_generation;
        auto self = reinterpret_cast<MsimePreviewEngine *>(source);
        std::unique_ptr<Json> snapshot(static_cast<Json *>(
            g_task_propagate_pointer(G_TASK(result), nullptr)));
        if (!self->state) return;
        const auto &request = *static_cast<MenuPreferenceSave *>(
            g_task_get_task_data(G_TASK(result)));
        guarded(IBUS_ENGINE(source), "menu_preference_save", [&] {
          if (request.configuration != configuration_generation) return;
          if (!snapshot) {
            failed_menu_save = FailedMenuSave{request.preference, request.value,
                                             request.directory, request.configuration};
            g_warning("Cannot save MSIME menu preference");
            publish_mode(IBUS_ENGINE(source));
            return;
          }
          // A concurrent reader may already have accepted a newer store revision.
          if (accepted_preferences_directory == request.directory &&
              !accepted_preferences_snapshot.is_null() &&
              accepted_preferences_snapshot.at("revision").get<uint64_t>() >
                  snapshot->at("revision").get<uint64_t>()) {
            *snapshot = accepted_preferences_snapshot;
          }
          if (request.preference == MenuPreference::CloudCandidates)
            self->state->cloud_candidates_override.reset();
          if (request.preference == MenuPreference::CandidateTranslations)
            self->state->candidate_translations_override.reset();
          if (request.preference == MenuPreference::TranslationLanguage)
            self->state->translation_target_language_override.reset();
          if (request.preference == MenuPreference::CandidateTheme)
            self->state->theme_override.reset();
          if (request.preference == MenuPreference::PreeditStyle)
            self->state->preedit_override.reset();
          if (request.preference == MenuPreference::CandidateLayout)
            self->state->layout_override.reset();
          if (request.preference == MenuPreference::CandidateSkin)
            self->state->skin_override.reset();
          if (request.preference == MenuPreference::CandidatePageSize)
            self->state->candidate_page_size_override.reset();
          if (request.preference == MenuPreference::FrequencyMode)
            self->state->frequency_mode_override.reset();
          if (request.preference == MenuPreference::SmartPunctuation)
            self->state->smart_punctuation_override.reset();
          if (request.preference == MenuPreference::SmartPunctuationRepeat)
            self->state->smart_repeat_override.reset();
          if (request.preference == MenuPreference::PairedPunctuation)
            self->state->paired_punctuation_override.reset();
          if (request.preference == MenuPreference::PunctuationLock)
            self->state->punctuation_lock_override.reset();
          if (request.preference == MenuPreference::AutocorrectTransposition)
            self->state->autocorrect_transposition_override.reset();
          if (request.preference == MenuPreference::AutocorrectNeighbor)
            self->state->autocorrect_neighbor_override.reset();
          if (request.preference == MenuPreference::EnglishCandidates)
            self->state->english_override.reset();
          if (request.preference == MenuPreference::EmojiCandidates)
            self->state->emoji_override.reset();
          if (request.preference == MenuPreference::KaomojiCandidates)
            self->state->kaomoji_override.reset();
          if (request.preference == MenuPreference::QuanpinHelpcode &&
              self->state->scheme_override.value_or(configured.at("preferences").value("scheme", "quanpin")) == "quanpin")
            self->state->helpcode_override.reset();
          if (request.preference == MenuPreference::QuanpinHelpcodeSchema &&
              self->state->scheme_override.value_or(configured.at("preferences").value("scheme", "quanpin")) == "quanpin")
            self->state->helpcode_schema_override.reset();
          if (request.preference == MenuPreference::ShuangpinHelpcode &&
              self->state->scheme_override.value_or(configured.at("preferences").value("scheme", "quanpin")) == "shuangpin")
            self->state->helpcode_override.reset();
          if (request.preference == MenuPreference::ShuangpinHelpcodeSchema &&
              self->state->scheme_override.value_or(configured.at("preferences").value("scheme", "quanpin")) == "shuangpin")
            self->state->helpcode_schema_override.reset();
          if (request.preference == MenuPreference::ShuangpinProfile)
            self->state->shuangpin_profile_override.reset();
          if (request.preference == MenuPreference::InputScheme)
            self->state->scheme_override.reset();
          if (request.preference == MenuPreference::NineKey)
            self->state->nine_key_override.reset();
          if (request.preference == MenuPreference::LocalMode)
            self->state->local_mode_overrides.erase(request.value.at("key").get<std::string>());
          if (request.preference == MenuPreference::NumberRowSelection)
            self->state->number_row_override.reset();
          if (request.preference == MenuPreference::WordCharacter)
            self->state->word_character_override.reset();
          if (request.preference == MenuPreference::TraditionalOutput)
            self->state->traditional_output_override.reset();
          if (request.preference == MenuPreference::InputMode)
            self->state->input_enabled = request.value.get<bool>();
          if (request.preference == MenuPreference::ChinesePunctuation)
            self->state->punctuation_override.reset();
          if (request.preference == MenuPreference::CharacterWidth)
            self->state->fullwidth = request.value.get<bool>();
          if (request.preference == MenuPreference::VoiceEnabled)
            self->state->voice_enabled = request.value.get<bool>();
          accepted_preferences_directory = request.directory;
          accepted_preferences_snapshot = *snapshot;
          configured["preferences"] = snapshot->at("preferences");
          apply_live_preferences(IBUS_ENGINE(source), *snapshot);
          publish_mode(IBUS_ENGINE(source));
        });
      }, nullptr);
  g_task_set_task_data(task, new MenuPreferenceSave{directory, configuration_generation, preference, std::move(value)},
      +[](gpointer value) { delete static_cast<MenuPreferenceSave *>(value); });
  g_task_run_in_thread(task,
      +[](GTask *task, gpointer, gpointer data, GCancellable *) {
        const auto &request = *static_cast<MenuPreferenceSave *>(data);
        Json *saved = nullptr;
        try {
          const auto *path = reinterpret_cast<const uint8_t *>(request.directory.data());
          auto snapshot = response(msime_client_load_preferences(path, request.directory.size()));
          const auto revision = snapshot.at("revision").get<uint64_t>();
          switch (request.preference) {
          case MenuPreference::CandidateTheme:
            snapshot["preferences"]["candidate_theme"] = request.value;
            break;
          case MenuPreference::PreeditStyle:
            snapshot["preferences"]["tsf_preedit_style"] = request.value;
            break;
          case MenuPreference::CandidateLayout:
            snapshot["preferences"]["candidate_layout"] = request.value;
            break;
          case MenuPreference::CandidateSkin:
            snapshot["preferences"]["candidate_skin"] = request.value;
            break;
          case MenuPreference::CandidatePageSize:
            snapshot["preferences"]["candidate_page_size"] = request.value;
            break;
          case MenuPreference::FrequencyMode:
            snapshot["preferences"]["frequency"]["mode"] = request.value;
            break;
          case MenuPreference::SmartPunctuation:
            snapshot["preferences"]["smart_punctuation"] = request.value;
            break;
          case MenuPreference::SmartPunctuationRepeat:
            snapshot["preferences"]["smart_punctuation_repeat"] = request.value;
            break;
          case MenuPreference::PairedPunctuation:
            snapshot["preferences"]["paired_punctuation"] = request.value;
            break;
          case MenuPreference::PunctuationLock:
            snapshot["preferences"]["punctuation_lock"] = request.value;
            break;
          case MenuPreference::AutocorrectTransposition:
            snapshot["preferences"]["quanpin"]["autocorrect_transposition"] = request.value;
            break;
          case MenuPreference::AutocorrectNeighbor:
            snapshot["preferences"]["quanpin"]["autocorrect_neighbor"] = request.value;
            break;
          case MenuPreference::EnglishCandidates:
            snapshot["preferences"]["mixed_input"]["english"] = request.value;
            break;
          case MenuPreference::EmojiCandidates:
            snapshot["preferences"]["mixed_input"]["emoji"] = request.value;
            break;
          case MenuPreference::KaomojiCandidates:
            snapshot["preferences"]["mixed_input"]["kaomoji"] = request.value;
            break;
          case MenuPreference::QuanpinHelpcode:
            snapshot["preferences"]["quanpin_helpcode"]["enabled"] = request.value;
            break;
          case MenuPreference::QuanpinHelpcodeSchema:
            snapshot["preferences"]["quanpin_helpcode"]["schema"] = request.value;
            break;
          case MenuPreference::ShuangpinHelpcode:
            snapshot["preferences"]["shuangpin_helpcode"]["enabled"] = request.value;
            break;
          case MenuPreference::ShuangpinHelpcodeSchema:
            snapshot["preferences"]["shuangpin_helpcode"]["schema"] = request.value;
            break;
          case MenuPreference::ShuangpinProfile:
            snapshot["preferences"]["shuangpin_profile"] = request.value;
            break;
          case MenuPreference::InputScheme:
            snapshot["preferences"]["scheme"] = request.value;
            if (request.value != "japanese")
              snapshot["preferences"]["last_chinese_scheme"] = request.value;
            break;
          case MenuPreference::NineKey:
            snapshot["preferences"]["touch_keyboard_layout"] =
                request.value.get<bool>() ? "nine_key" : "twenty_six_key";
            break;
          case MenuPreference::LocalMode:
            snapshot["preferences"]["local_modes"][request.value.at("key").get<std::string>()] =
                request.value.at("enabled");
            break;
          case MenuPreference::NumberRowSelection:
            snapshot["preferences"]["number_row_selection"] = request.value;
            break;
          case MenuPreference::WordCharacter:
            snapshot["preferences"]["word_character"]["enabled"] = request.value;
            break;
          case MenuPreference::TraditionalOutput:
            snapshot["preferences"]["traditional_chinese_output"] = request.value;
            break;
          case MenuPreference::ChinesePunctuation:
            snapshot["preferences"]["chinese_punctuation"] = request.value;
            break;
          case MenuPreference::InputMode:
            snapshot["preferences"]["ime_mode"] = request.value.get<bool>() ? "chinese" : "english";
            break;
          case MenuPreference::ClipboardHistoryEnabled:
            snapshot["preferences"]["clipboard_history"] = request.value;
            break;
          case MenuPreference::CharacterWidth:
            snapshot["preferences"]["character_width"] = request.value.get<bool>() ? "fullwidth" : "halfwidth";
            break;
          case MenuPreference::VoiceEnabled:
            snapshot["preferences"]["voice_input"]["enabled"] = request.value;
            break;
          case MenuPreference::Toolbar:
            snapshot["preferences"]["floating_toolbar"]["enabled"] = request.value;
            break;
          case MenuPreference::CloudCandidates:
            snapshot["preferences"]["cloud_candidates"] = request.value;
            break;
          case MenuPreference::CandidateTranslations:
            snapshot["preferences"]["candidate_translations"] = request.value;
            break;
          case MenuPreference::TranslationLanguage:
            snapshot["preferences"]["translation_target_language"] = request.value;
            break;
          }
          const auto encoded = snapshot.dump();
          saved = new Json(response(msime_client_save_preferences(
              path, request.directory.size(), revision,
              reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size())));
        } catch (...) {
          // Revision conflicts and storage errors leave the visible setting unchanged.
        }
        g_task_return_pointer(task, saved,
            +[](gpointer value) { delete static_cast<Json *>(value); });
      });
  g_object_unref(task);
}
gboolean reload_preferences(gpointer data) {
  auto engine = IBUS_ENGINE(data);
  auto &s = state(engine);
  // Saving is shared across contexts, but only the initiating context receives
  // the task callback. Refresh status even when preferences did not change or
  // a preference read is still in flight (including failed saves).
  if (s.focused && !s.blocked &&
      (s.seen_menu_status_generation != menu_status_generation ||
       s.seen_menu_configuration != configuration_generation)) {
    guarded(engine, "menu_status", [&] {
      publish_mode(engine);
      s.seen_menu_status_generation = menu_status_generation;
      s.seen_menu_configuration = configuration_generation;
    });
  }
  watch_clipboard_history(engine);
  guarded(engine, "provider_discovery", [&] {
    if (s.refresh_provider_sockets(engine) && s.focused && !s.blocked) {
      if (s.translation_reset_pending)
        clear_candidate_translations(engine);
      publish_mode(engine);
      online_schedule(engine);
      translation_schedule(engine);
    }
  });
  if (s.preferences_loading)
    return G_SOURCE_CONTINUE;
  const auto directory = configured.find("preferences_directory");
  if (directory == configured.end() || !directory->is_string() ||
      directory->get<std::string>().empty() ||
      directory->get<std::string>().front() != '/') {
    guarded(engine, "runtime_preferences", [&] {
      apply_live_preferences(engine, Json{{"format_version", 1}, {"revision", 0},
                                         {"preferences", configured.at("preferences")}});
    });
    return G_SOURCE_CONTINUE;
  }
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
                           if (!request || !raw ||
                               request->configuration_generation != configuration_generation)
                             return;
                           try {
                             auto snapshot = response(raw.release());
                             if (snapshot.is_null())
                               return;
                             const auto revision = snapshot.at("revision").get<uint64_t>();
                             if (accepted_preferences_directory == request->directory &&
                                 !accepted_preferences_snapshot.is_null()) {
                               const auto accepted_revision =
                                   accepted_preferences_snapshot.at("revision").get<uint64_t>();
                               if (revision < accepted_revision ||
                                   (revision == accepted_revision &&
                                    snapshot.at("preferences") !=
                                        accepted_preferences_snapshot.at("preferences")))
                                 return;
                             }
                             accepted_preferences_directory = request->directory;
                             accepted_preferences_snapshot = snapshot;
                             configured["preferences"] = snapshot.at("preferences");
                             if (s.session != request->session || !s.focused ||
                                 s.blocked)
                               return;
                             apply_live_preferences(IBUS_ENGINE(source), std::move(snapshot));
                           } catch (...) {
                             // Retry on the next tick without logging paths or input.
                           }
                         },
                         nullptr);
  g_task_set_task_data(
      task,
      new PreferencesRead{directory->get<std::string>(), s.session, configuration_generation},
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
  engine->state->wave_overlay_surface =
      msime::linux_host::create_wave_overlay_surface(IBUS_ENGINE(engine));
  engine->state->client_token = next_client_token.fetch_add(1, std::memory_order_relaxed);
  // Seed once per host instance; refocus or session recreation keeps user choice.
  if (configured.is_object())
    engine->state->input_enabled = configured.at("preferences").value(
        "default_ime_mode", "chinese") != "english";
  engine->state->preferences_timer =
      g_timeout_add(1000, reload_preferences, engine);
}
static void msime_preview_engine_class_init(MsimePreviewEngineClass *klass) {
  auto engine = IBUS_ENGINE_CLASS(klass);
  engine->process_key_event = process_key;
  engine->property_activate = property_activate;
  engine->enable = [](IBusEngine *engine) {
    // Advertise surrounding-text use so native IM modules send document updates.
    ibus_engine_get_surrounding_text(engine, nullptr, nullptr, nullptr);
  };
  engine->focus_in = focus_in;
  engine->focus_out = focus_out;
#if IBUS_CHECK_VERSION(1, 5, 27)
  engine->focus_in_id = [](IBusEngine *engine, const gchar *context, const gchar *client) {
    auto &s = state(engine);
    if (s.focused && !s.focused_context.empty() &&
        s.focused_context != (context ? context : ""))
      focus_out(engine);
    s.focused_context = context ? context : "";
    s.surrounding_utf16 = g_strcmp0(client, "QIBusInputContext") == 0;
    focus_in(engine);
  };
  engine->focus_out_id = [](IBusEngine *engine, const gchar *context) {
    const auto &current = state(engine).focused_context;
    if (!current.empty() && current != (context ? context : ""))
      return;
    focus_out(engine);
  };
#endif
  engine->disable = [](IBusEngine *engine) {
    focus_out(engine);
    guarded(engine, "disable", [&] {
      // IBus disables the old engine when changing input sources. Unlike a
      // focus transfer, reactivation must start from the configured CN/EN mode.
      global_input_enabled.reset();
      // The daemon clears properties on disable; register them on reactivation.
      state(engine).properties_registered = false;
      state(engine).input_enabled = configured.at("preferences").value(
          "default_ime_mode", "chinese") != "english";
    });
  };
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
  auto next = Json::parse(options);
  if (!next.is_object() || !next.contains("preferences") ||
      !next.at("preferences").is_object())
    throw std::runtime_error("Invalid host preferences");
  if (next != configured) {
    configured = std::move(next);
    ++configuration_generation;
  }
}
void msime_preview_set_system_dark(bool dark) {
  if (system_dark != dark) {
    system_dark = dark;
    ++configuration_generation;
  }
}

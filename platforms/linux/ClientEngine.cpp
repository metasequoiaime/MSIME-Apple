#include "ClientEngine.h"
#include "NavigationBindings.h"
#include "WordCharacterBinding.h"
#include "VoiceWorker.h"
#include "msime_client.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <fcntl.h>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <tuple>
#include <cstdlib>
#include <stdexcept>
#include <sys/file.h>
#include <unistd.h>

using Json = nlohmann::json;
struct MsimePreviewEngine;
namespace {
Json configured;
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
struct State {
  MsimeVoiceWorker voice_worker;
  uint64_t session = 0;
  Json view;
  bool focused = false;
  bool blocked = false;
  bool private_input = false;
  bool input_enabled = true;
  bool chinese_punctuation = true;
  bool properties_registered = false;
  std::optional<bool> english_override;
  std::optional<bool> emoji_override;
  std::optional<bool> kaomoji_override;
  std::optional<bool> punctuation_override, autocorrect_override, helpcode_override;
  std::optional<bool> word_character_override;
  std::optional<bool> smart_punctuation_override, smart_repeat_override, paired_punctuation_override;
  std::optional<std::string> punctuation_lock_override;
  std::optional<uint8_t> candidate_page_size_override;
  std::optional<std::string> frequency_mode_override, helpcode_schema_override;
  std::optional<std::string> layout_override, preedit_override, theme_override;
  std::optional<std::string> skin_override, scheme_override, shuangpin_profile_override;
  bool fullwidth = false;
  bool smart_punctuation = true;
  bool smart_punctuation_repeat = true;
  bool paired_punctuation = true;
  bool pure_shift_candidate = false;
  bool number_row_selection = true;
  char last_smart_punctuation = 0;
  gint64 last_smart_punctuation_time = 0;
  std::string punctuation_lock = "follow";
  std::string preedit_style = "raw";
  std::optional<guint> candidate_text_color, candidate_background_color;
  IBusOrientation candidate_orientation = IBUS_ORIENTATION_VERTICAL;
  msime::linux_host::NavigationBindings navigation;
  msime::linux_host::WordCharacterBinding word_character;
  std::string clipboard_history_path, online_provider_socket;
  std::vector<std::string> clipboard_items_cache;
  uint64_t clipboard_generation = 0;
  bool clipboard_loading = false, clipboard_loaded = false;
  bool online_loading = false, translation_loading = false;
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
    voice_worker.cancel();
    close();
  }
  void close() {
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
  }
  void open() {
    if (session || blocked || !focused || !input_enabled)
      return;
    auto options = configured;
    number_row_selection = options.value("preferences", Json::object()).value("number_row_selection", true);
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
    }
    clipboard_history_path = options.value("clipboard_history_path", std::string{});
    online_provider_socket = options.value("online_provider_socket", std::string{});
    if (english_override)
      options["preferences"]["mixed_input"]["english"] = *english_override;
    if (emoji_override)
      options["preferences"]["mixed_input"]["emoji"] = *emoji_override;
    if (kaomoji_override)
      options["preferences"]["mixed_input"]["kaomoji"] = *kaomoji_override;
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
    if (options.at("preferences").value("default_ime_mode", "chinese") == "english")
      view = response(msime_client_set_english_mode(session, true));
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
    view = response(
        msime_client_set_chinese_punctuation(session, chinese_punctuation));
    navigation = bindings;
    word_character = edge_binding;
    if (word_character_override)
      word_character.enabled = *word_character_override;
  }
};
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
bool apply(IBusEngine *engine, char *raw);
void render(IBusEngine *engine, const Json &view);
void translation_complete(GObject *source, GAsyncResult *result, gpointer);
void translation_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_provider_socket.empty() || s.translation_loading || !s.session ||
      !s.focused || s.blocked || !s.input_enabled || !s.view.value("candidates", Json::array()).size())
    return;
  try {
    auto query = response(msime_client_translation_query(s.session));
    if (query.is_null() || !query.is_object()) return;
    auto *task_data = new TranslationTask{s.session, s.provider_epoch, query.dump(), s.online_provider_socket};
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
void online_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_provider_socket.empty() || s.online_loading || !s.session ||
      !s.focused || s.blocked || !s.input_enabled)
    return;
  try {
    auto query = response(msime_client_online_query(s.session));
    if (!query.is_object() ||
        !(query.value("cloud_eligible", false) || query.value("ai_eligible", false)))
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
  if (!raw || !s.session || !s.focused || s.blocked || !s.input_enabled) return;
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
  if (!raw || !s.session || !s.focused || s.blocked || !s.input_enabled) return;
  try {
    const auto document = Json::parse(raw.get());
    if (!document.value("ok", false)) return;
    const auto value = document.at("value");
    const auto candidate = value.value("text", std::string{});
    if (candidate.empty()) return;
    auto applied = response(msime_client_apply_online_candidate(
        s.session, reinterpret_cast<const uint8_t *>(request->query.data()), request->query.size(),
        reinterpret_cast<const uint8_t *>(candidate.data()), candidate.size(),
        static_cast<uint8_t>(value.value("source", 0))));
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
IBusProperty *candidate_actions(IBusEngine *engine) {
  const auto &s = state(engine);
  auto items = ibus_prop_list_new();
  const auto candidates = s.view.is_object()
                              ? s.view.value("candidates", Json::array())
                              : Json::array();
  size_t slot = 0;
  for (const auto &candidate : candidates) {
    if (!candidate.is_object() || !candidate.contains("id") ||
        !candidate.at("id").is_object())
      continue;
    const auto &id = candidate.at("id");
    if (!id.contains("session") || !id.contains("generation") || !id.contains("index") ||
        !id.at("session").is_number_unsigned() || !id.at("generation").is_number_unsigned() ||
        !id.at("index").is_number_unsigned())
      continue;
    ++slot;
    for (const auto &[action, label] : {std::pair{"CandidatePin", "固定候选"},
                                       std::pair{"CandidateRemove", "删除候选"}}) {
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
      s.session && s.focused && !s.blocked && s.input_enabled && !candidates.empty(),
      TRUE, PROP_STATE_UNCHECKED, items);
}
void publish_mode(IBusEngine *engine, bool registration) {
  auto &s = state(engine);
  clipboard_schedule(engine);
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
  auto english = ibus_property_new(
      "EnglishCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充英文候选"),
      s.focused && !s.blocked && s.input_enabled, TRUE,
      english_candidates ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
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
        (std::string("Scheme/") + (value == "quanpin" ? "Quanpin" : value == "shuangpin" ? "Shuangpin" : "Wubi")).c_str(), PROP_TYPE_RADIO,
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
    ibus_prop_list_append(properties, candidate_actions(engine));
    ibus_prop_list_append(properties, property);
    ibus_prop_list_append(properties, punctuation);
    ibus_prop_list_append(properties, smart_punctuation);
    ibus_prop_list_append(properties, smart_repeat);
    ibus_prop_list_append(properties, paired);
    ibus_prop_list_append(properties, punctuation_lock);
    ibus_prop_list_append(properties, character_mode);
    ibus_prop_list_append(properties, english);
    ibus_prop_list_append(properties, autocorrect_property);
    ibus_prop_list_append(properties, helpcode_property);
    ibus_prop_list_append(properties, helpcode_schema);
    ibus_prop_list_append(properties, emoji);
    ibus_prop_list_append(properties, kaomoji);
    ibus_prop_list_append(properties, clipboard);
    ibus_prop_list_append(properties, layout_property);
    ibus_prop_list_append(properties, page_size_property);
    ibus_prop_list_append(properties, frequency_property);
    ibus_prop_list_append(properties, word_character_property);
    ibus_prop_list_append(properties, preedit_property);
    ibus_prop_list_append(properties, theme_property);
    ibus_prop_list_append(properties, skin_property);
    ibus_prop_list_append(properties, scheme);
    ibus_prop_list_append(properties, profile);
    ibus_engine_register_properties(engine, properties);
  } else {
    ibus_engine_update_property(engine, candidate_actions(engine));
    ibus_engine_update_property(engine, property);
    ibus_engine_update_property(engine, punctuation);
    ibus_engine_update_property(engine, smart_punctuation);
    ibus_engine_update_property(engine, smart_repeat);
    ibus_engine_update_property(engine, paired);
    ibus_engine_update_property(engine, punctuation_lock);
    ibus_engine_update_property(engine, character_mode);
    ibus_engine_update_property(engine, english);
    ibus_engine_update_property(engine, autocorrect_property);
    ibus_engine_update_property(engine, helpcode_property);
    ibus_engine_update_property(engine, helpcode_schema);
    ibus_engine_update_property(engine, emoji);
    ibus_engine_update_property(engine, kaomoji);
    ibus_engine_update_property(engine, clipboard);
    ibus_engine_update_property(engine, layout_property);
    ibus_engine_update_property(engine, page_size_property);
    ibus_engine_update_property(engine, frequency_property);
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
void publish_input_enabled(IBusEngine *engine, bool enabled) {
  auto property = ibus_property_new(
      "InputEnabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("输入启用"), "",
      ibus_text_new_from_static_string("启用或停用当前 Linux 输入会话"), TRUE,
      TRUE, enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
void publish_punctuation(IBusEngine *engine, bool enabled) {
  auto property = ibus_property_new(
      "ChinesePunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("启用中文标点转换"), TRUE, TRUE,
      enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
void publish_character_width(IBusEngine *engine, bool fullwidth) {
  auto property = ibus_property_new(
      "CharacterWidth", PROP_TYPE_TOGGLE, ibus_text_new_from_static_string("全角字符"), "",
      ibus_text_new_from_static_string("切换 ASCII 字符的全角/半角输出"), TRUE, TRUE,
      fullwidth ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
}
void publish_expressive(IBusEngine *engine, const State &s) {
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
    if (candidate.contains("translation") && !candidate.at("translation").is_null()) {
      auto translation = candidate.at("translation").get<std::string>();
      // IBus lookup rows are plain text; preserve the candidate and expose
      // the optional gloss without allowing an oversized provider result to
      // destabilize the panel.
      if (!translation.empty() && translation.size() <= 4096 &&
          value.size() <= 4096)
        value += " · " + translation;
    }
    const auto annotation = candidate.value("annotation", std::string{});
    if (!annotation.empty()) {
      value += "  ";
      value += annotation;
    }
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
bool apply(IBusEngine *engine, char *raw) {
  auto result = response(raw);
  const auto &commit = result.at("commit");
  if (commit.is_string()) {
    auto text = commit.get<std::string>();
    auto &s = state(engine);
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
    if (s.session)
      apply(engine, msime_client_focus(s.session, true));
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
    s.focused = false;
    s.invalidate_providers();
    s.surrounding_text.clear();
    s.surrounding_cursor = 0;
    s.surrounding_anchor = 0;
    if (s.session)
      apply(engine, msime_client_focus(s.session, false));
    clear(engine);
    publish_mode(engine);
  });
}
void property_activate(IBusEngine *engine, const gchar *name, guint value) {
  const std::string candidate_name = name ? name : "";
  if (candidate_name.rfind("CandidatePin", 0) == 0 ||
      candidate_name.rfind("CandidateRemove", 0) == 0) {
    guarded(engine, "candidate_property", [&] {
      auto &s = state(engine);
      if (!s.session || !s.focused || s.blocked || !s.input_enabled)
        return;
      for (const auto &candidate : s.view.at("candidates")) {
        const auto &id = candidate.at("id");
        const bool pin = candidate_name == candidate_action_name("CandidatePin", id);
        if (!pin && candidate_name != candidate_action_name("CandidateRemove", id))
          continue;
        if (id.at("session").get<uint64_t>() != s.session)
          return;
        const auto generation = id.at("generation").get<uint64_t>();
        const auto index = id.at("index").get<size_t>();
        apply(engine, pin ? msime_client_pin_candidate(s.session, generation, index)
                          : msime_client_remove_candidate(s.session, generation, index));
        return;
      }
    });
    return;
  }
  auto &s = state(engine);
  const std::string property_name = name ? name : "";
  const bool clipboard_item = property_name.rfind("ClipboardHistory/", 0) == 0 &&
                               property_name != "ClipboardHistory/Latest" &&
                               property_name != "ClipboardHistory/Clear" &&
                               property_name.rfind("ClipboardHistory/Remove/", 0) != 0;
  const bool clipboard_remove = property_name.rfind("ClipboardHistory/Remove/", 0) == 0;
  if (!name ||
       (!(clipboard_item || clipboard_remove) && property_name != "ClipboardHistory/Clear" &&
       std::string(name) != "InputMode" &&
       std::string(name) != "Punctuation" &&
       std::string(name) != "SmartPunctuation" &&
       std::string(name) != "SmartPunctuationRepeat" &&
       std::string(name) != "PairedPunctuation" &&
       std::string(name) != "PunctuationLock/follow" &&
       std::string(name) != "PunctuationLock/chinese" &&
       std::string(name) != "PunctuationLock/english" &&
       std::string(name) != "CharacterMode" &&
       std::string(name) != "EnglishCandidates" &&
       std::string(name) != "Autocorrect" &&
       std::string(name) != "Helpcode" &&
       property_name.rfind("HelpcodeSchema/", 0) != 0 &&
       std::string(name) != "EmojiCandidates" &&
       std::string(name) != "KaomojiCandidates" &&
       std::string(name) != "CandidateLayout/Vertical" &&
       std::string(name) != "CandidateLayout/Horizontal" &&
       property_name.rfind("CandidatePageSize/", 0) != 0 &&
       property_name.rfind("FrequencyMode/", 0) != 0 &&
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
  guarded(engine, [&] {
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
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuation") {
      s.smart_punctuation = value == PROP_STATE_CHECKED;
      s.smart_punctuation_override = s.smart_punctuation;
      if (!s.smart_punctuation)
        s.last_smart_punctuation = 0;
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuationRepeat") {
      s.smart_punctuation_repeat = value == PROP_STATE_CHECKED;
      s.smart_repeat_override = s.smart_punctuation_repeat;
      if (!s.smart_punctuation_repeat)
        s.last_smart_punctuation = 0;
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "CharacterMode") {
      s.fullwidth = value == PROP_STATE_CHECKED;
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
      if (!enabled && s.session)
        apply(engine,
              msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
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
gboolean process_key(IBusEngine *engine, guint key, guint, guint flags) {
  auto &s = state(engine);
  const bool shift_key = key == IBUS_Shift_L || key == IBUS_Shift_R;
  if (shift_key && (flags & IBUS_RELEASE_MASK)) {
    if (!s.pure_shift_candidate)
      return FALSE;
    s.pure_shift_candidate = false;
    if (!s.focused || s.blocked)
      return FALSE;
    if (!s.view.is_null() && !s.view.at("editing_text").get<std::string>().empty())
      return FALSE;
    guarded(engine, [&] {
      s.open();
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.input_enabled = !s.input_enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, s.input_enabled));
      clear(engine);
      publish_mode(engine);
    });
    return TRUE;
  }
  if (shift_key && !(flags & IBUS_RELEASE_MASK)) {
    s.pure_shift_candidate = true;
    return FALSE;
  }
  if (!(flags & IBUS_RELEASE_MASK))
    s.pure_shift_candidate = false;
  const guint modifiers = flags & (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK |
                                   IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
                                   IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK);
  const bool english_toggle =
      key == IBUS_e && (flags & (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK)) ==
                            (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK);
  const bool mode_toggle =
      english_toggle ||
      (key == IBUS_space &&
       (((flags & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK)) == IBUS_CONTROL_MASK) ||
        ((flags & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK)) ==
         (IBUS_CONTROL_MASK | IBUS_MOD1_MASK))));
  const bool fullwidth_toggle =
      (key == IBUS_space || key == IBUS_f) &&
      modifiers == (IBUS_CONTROL_MASK | IBUS_SHIFT_MASK);
  if (!s.focused || s.blocked || (!s.input_enabled && !mode_toggle && !fullwidth_toggle) ||
      (flags & IBUS_RELEASE_MASK))
    return FALSE;
  if (fullwidth_toggle) {
    s.fullwidth = !s.fullwidth;
    return TRUE;
  }
  if (modifier(key))
    return FALSE;
  bool handled = false;
  guarded(engine, "process_key", [&] {
    s.open();
    if ((flags & IBUS_CONTROL_MASK) && key == IBUS_space) {
      s.input_enabled = !s.input_enabled;
      if (s.session)
        apply(engine, msime_client_focus(s.session, s.input_enabled));
      clear(engine);
      publish_punctuation(engine, s.chinese_punctuation);
      handled = true;
      return;
    }
    if (!s.input_enabled)
      return;
    if (!s.view.at("focused").get<bool>())
      apply(engine, msime_client_focus(s.session, true));
    // Apply configured candidate bindings before punctuation can consume them.
    if ((modifiers & ~IBUS_SHIFT_MASK) == 0 &&
        !s.view.at("candidates").empty()) {
      if (const auto edge = s.word_character.edge(key, (flags & IBUS_SHIFT_MASK) != 0)) {
        handled = apply(engine, msime_client_command(s.session, *edge));
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
    if (s.chinese_punctuation && s.paired_punctuation &&
        !(flags & (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_SUPER_MASK)) &&
        s.view.at("editing_text").get<std::string>().empty() &&
        (key == IBUS_quotedbl || key == IBUS_apostrophe)) {
      const char *pair = key == IBUS_quotedbl ? "“”" : "‘’";
      ibus_engine_commit_text(engine, ibus_text_new_from_string(pair));
      handled = true;
      return;
    }
    if ((flags & IBUS_CONTROL_MASK) && key == IBUS_period) {
      s.chinese_punctuation = !s.chinese_punctuation;
      s.punctuation_override = s.chinese_punctuation;
      s.view = response(msime_client_set_chinese_punctuation(
          s.session, s.chinese_punctuation));
      render(engine, s.view);
      publish_mode(engine);
      handled = true;
      return;
    }
    if (s.smart_punctuation_repeat && s.paired_punctuation && s.last_smart_punctuation == key &&
        s.last_smart_punctuation_time != 0 &&
        g_get_monotonic_time() - s.last_smart_punctuation_time <= 500000 &&
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
    if (!s.smart_punctuation && s.view.at("editing_text").get<std::string>().empty() &&
        std::string("`~!@#$%^&*()-_=+[]{}\\;:'\",.<>/?").find(key) !=
            std::string::npos) {
      char raw[2] = {static_cast<char>(key), '\0'};
      ibus_engine_commit_text(engine, ibus_text_new_from_string(raw));
      handled = true;
      return;
    }
    if (flags &
        (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
         IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK)) {
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
      return;
    }
    if (s.number_row_selection && !s.view.at("candidates").empty() && modifiers == 0 && key >= IBUS_0 && key <= IBUS_9) {
      const size_t index = key == IBUS_0 ? 9 : static_cast<size_t>(key - IBUS_1);
      if (index >= s.view.at("candidates").size()) return;
      const auto &candidate = s.view.at("candidates").at(index);
      handled = apply(engine, msime_client_select(
          s.session, candidate.at("id").at("generation").get<uint64_t>(), index));
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
    else
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
  });
  return handled;
}
void candidate_clicked(IBusEngine *engine, guint index, guint button,
                       guint flags) {
  if (button != 1 || flags || !state(engine).focused || state(engine).blocked ||
      !state(engine).input_enabled)
    return;
  guarded(engine, "candidate_clicked", [&] {
    auto &s = state(engine);
    const auto candidates = s.view.value("candidates", Json::array());
    if (!s.session || !candidates.is_array() || index >= candidates.size())
      return;
    const auto &entry = candidates.at(index);
    if (!entry.is_object() || !entry.contains("id") || !entry.at("id").is_object())
      return;
    auto id = entry.at("id");
    if (id.at("session").get<uint64_t>() != s.session)
      return;
    apply(engine,
          msime_client_select(s.session, id.at("generation").get<uint64_t>(),
                              id.at("index").get<size_t>()));
  });
}
void page(IBusEngine *engine, uint32_t command) {
  guarded(engine, "page", [&] {
    auto &s = state(engine);
    if (s.session && s.focused && !s.blocked && s.input_enabled)
      apply(engine, msime_client_command(s.session, command));
  });
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

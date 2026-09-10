#include "ClientEngine.h"
#include "NavigationBindings.h"
#include "WordCharacterBinding.h"
#include "msime_client.h"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <fcntl.h>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <stdexcept>
#include <sys/file.h>
#include <unistd.h>

using Json = nlohmann::json;
struct MsimePreviewEngine;
namespace {
Json configured;
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
  uint64_t session = 0;
  Json view;
  bool focused = false;
  bool blocked = false;
  bool private_input = false;
  bool fullwidth = false;
  bool input_enabled = true;
  bool pure_shift_candidate = false;
  std::optional<bool> english_override;
  std::optional<bool> emoji_override;
  std::optional<bool> kaomoji_override;
  std::optional<std::string> layout_override;
  std::optional<std::string> preedit_override;
  std::optional<std::string> theme_override;
  std::optional<std::string> scheme_override;
  bool chinese_punctuation = true;
  bool smart_punctuation = true;
  bool smart_punctuation_repeat = true;
  char last_smart_punctuation = 0;
  gint64 last_smart_punctuation_time = 0;
  std::string punctuation_lock = "follow";
  std::optional<guint> candidate_text_color;
  std::optional<guint> candidate_background_color;
  IBusOrientation candidate_orientation = IBUS_ORIENTATION_VERTICAL;
  std::string preedit_style = "raw";
  std::optional<bool> punctuation_override;
  guint preferences_timer = 0;
  bool preferences_loading = false;
  std::string online_provider_socket;
  bool online_loading = false;
  std::string clipboard_history_path;
  std::vector<std::string> clipboard_items_cache;
  uint64_t clipboard_generation = 0;
  bool clipboard_loading = false;
  bool clipboard_loaded = false;
  msime::linux_host::NavigationBindings navigation;
  msime::linux_host::WordCharacterBinding word_character;
  ~State() { close(); }
  void close() {
    if (session)
      msime_client_string_free(msime_client_destroy(session));
    session = 0;
    view = nullptr;
    online_loading = false;
    clipboard_loading = false;
    clipboard_loaded = false;
    clipboard_items_cache.clear();
    ++clipboard_generation;
  }
  void open() {
    if (session || blocked || !focused || !input_enabled)
      return;
    auto options = configured;
    clipboard_history_path = options.value("clipboard_history_path", "");
    online_provider_socket = options.value("online_provider_socket", "");
    if (scheme_override)
      options["preferences"]["scheme"] = *scheme_override;
    if (english_override)
      options["preferences"]["mixed_input"]["english"] = *english_override;
    if (emoji_override)
      options["preferences"]["mixed_input"]["emoji"] = *emoji_override;
    if (kaomoji_override)
      options["preferences"]["mixed_input"]["kaomoji"] = *kaomoji_override;
    if (layout_override)
      options["preferences"]["candidate_layout"] = *layout_override;
    if (preedit_override)
      options["preferences"]["tsf_preedit_style"] = *preedit_override;
    if (theme_override)
      options["preferences"]["candidate_theme"] = *theme_override;
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
    chinese_punctuation = punctuation_override.value_or(
        options.at("preferences").value("chinese_punctuation", true));
    punctuation_lock = configured.value("punctuation_lock", "follow");
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
  const auto theme = preferences.value("candidate_theme", "follow");
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
  std::string query;
  std::string socket;
};
void online_complete(GObject *source, GAsyncResult *result, gpointer);
void online_schedule(IBusEngine *engine) {
  auto &s = state(engine);
  if (s.online_provider_socket.empty() || s.online_loading || !s.session ||
      !s.focused || s.blocked)
    return;
  try {
    auto query = response(msime_client_online_query(s.session));
    if (!query.value("available", false))
      return;
    auto *task_data = new OnlineTask{s.session, query.dump(), s.online_provider_socket};
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
  if (request->generation != s.clipboard_generation || !s.focused || s.blocked ||
      request->path != s.clipboard_history_path)
    return;
  auto *items = static_cast<std::vector<std::string> *>(
      g_task_propagate_pointer(G_TASK(result), nullptr));
  if (!items)
    return;
  s.clipboard_items_cache = std::move(*items);
  s.clipboard_loaded = true;
  delete items;
  publish_mode(IBUS_ENGINE(source));
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
  const auto layout = s.layout_override.value_or(
      configured.at("preferences").value("candidate_layout", "vertical"));
  const auto preedit = s.preedit_override.value_or(
      configured.at("preferences").value("tsf_preedit_style", "raw"));
  const auto theme = s.theme_override.value_or(
      configured.at("preferences").value("candidate_theme", "follow"));
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
  ibus_property_set_sub_props(scheme, scheme_menu);
  if (registration) {
    auto properties = ibus_prop_list_new();
    ibus_prop_list_append(properties, property);
    ibus_prop_list_append(properties, punctuation);
    ibus_prop_list_append(properties, smart_punctuation);
    ibus_prop_list_append(properties, smart_repeat);
    ibus_prop_list_append(properties, punctuation_lock);
    ibus_prop_list_append(properties, character_mode);
    ibus_prop_list_append(properties, english);
    ibus_prop_list_append(properties, emoji);
    ibus_prop_list_append(properties, kaomoji);
    ibus_prop_list_append(properties, clipboard);
    ibus_prop_list_append(properties, layout_property);
    ibus_prop_list_append(properties, preedit_property);
    ibus_prop_list_append(properties, theme_property);
    ibus_prop_list_append(properties, scheme);
    ibus_engine_register_properties(engine, properties);
  } else {
    ibus_engine_update_property(engine, property);
    ibus_engine_update_property(engine, punctuation);
    ibus_engine_update_property(engine, smart_punctuation);
    ibus_engine_update_property(engine, smart_repeat);
    ibus_engine_update_property(engine, punctuation_lock);
    ibus_engine_update_property(engine, character_mode);
    ibus_engine_update_property(engine, english);
    ibus_engine_update_property(engine, emoji);
    ibus_engine_update_property(engine, kaomoji);
    ibus_engine_update_property(engine, clipboard);
    ibus_engine_update_property(engine, layout_property);
    ibus_engine_update_property(engine, preedit_property);
    ibus_engine_update_property(engine, theme_property);
    ibus_engine_update_property(engine, scheme);
  }
}
void clear(IBusEngine *engine) {
  ibus_engine_update_preedit_text_with_mode(
      engine, ibus_text_new_from_static_string(""), 0, FALSE,
      IBUS_ENGINE_PREEDIT_CLEAR);
  ibus_engine_hide_lookup_table(engine);
  ibus_engine_hide_auxiliary_text(engine);
}
void render(IBusEngine *engine, const Json &view) {
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
    const auto annotation = candidate.value("annotation", "");
    if (!annotation.empty()) {
      label += " ";
      label += annotation;
    }
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
    if (s.smart_punctuation && text.size() == 1 &&
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
  return result.at("handled").get<bool>();
}
void online_complete(GObject *source, GAsyncResult *result, gpointer) {
  auto *engine = IBUS_ENGINE(source);
  auto &s = state(engine);
  auto *request = static_cast<OnlineTask *>(g_task_get_task_data(G_TASK(result)));
  s.online_loading = false;
  auto *raw = g_task_propagate_pointer(G_TASK(result), nullptr);
  if (!raw || !request || !s.session || s.session != request->session || !s.focused)
    return;
  try {
    auto reply = response(static_cast<char *>(raw));
    if (reply.is_null() || !reply.is_object() || !reply.contains("text") ||
        !reply.at("text").is_string() || !reply.contains("source"))
      return;
    auto text = reply.at("text").get<std::string>();
    auto source_id = reply.at("source").get<uint8_t>();
    auto query_bytes = request->query;
    s.online_loading = true;
    apply(engine, msime_client_apply_online_candidate(
                       s.session, reinterpret_cast<const uint8_t *>(query_bytes.data()),
                       query_bytes.size(), reinterpret_cast<const uint8_t *>(text.data()),
                       text.size(), source_id));
    s.online_loading = false;
  } catch (...) {
    g_warning("MSIME online provider result rejected");
  }
}
template <class F> void guarded(IBusEngine *engine, F action) noexcept {
  try {
    action();
  } catch (...) {
    // Never log the raw error or response: either can include input or paths.
    g_warning("MSIME preview host operation failed");
    state(engine).close();
    clear(engine);
    publish_mode(engine);
  }
}
void focus_in(IBusEngine *engine) {
  guarded(engine, [&] {
    auto &s = state(engine);
    s.focused = true;
    s.open();
    if (s.session)
      apply(engine, msime_client_focus(s.session, s.input_enabled));
    publish_mode(engine, true);
  });
}
void focus_out(IBusEngine *engine) {
  guarded(engine, [&] {
    auto &s = state(engine);
    s.focused = false;
    if (s.session)
      apply(engine, msime_client_focus(s.session, false));
    clear(engine);
    publish_mode(engine);
  });
}
void property_activate(IBusEngine *engine, const gchar *name, guint value) {
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
       std::string(name) != "PunctuationLock/follow" &&
       std::string(name) != "PunctuationLock/chinese" &&
       std::string(name) != "PunctuationLock/english" &&
       std::string(name) != "CharacterMode" &&
       std::string(name) != "EnglishCandidates" &&
       std::string(name) != "EmojiCandidates" &&
       std::string(name) != "KaomojiCandidates" &&
       std::string(name) != "CandidateLayout/Vertical" &&
       std::string(name) != "CandidateLayout/Horizontal" &&
       std::string(name) != "PreeditStyle/raw" &&
       std::string(name) != "PreeditStyle/pinyin" &&
       std::string(name) != "PreeditStyle/empty" &&
       std::string(name) != "CandidateTheme/follow" &&
       std::string(name) != "CandidateTheme/light" &&
       std::string(name) != "CandidateTheme/dark" &&
       std::string(name) != "Scheme/Chinese" &&
       std::string(name) != "Scheme/Japanese") ||
      !s.focused || s.blocked ||
      (value != PROP_STATE_CHECKED && value != PROP_STATE_UNCHECKED))
    return;
  guarded(engine, [&] {
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
    if (std::string(name) == "SmartPunctuation") {
      s.smart_punctuation = value == PROP_STATE_CHECKED;
      if (!s.smart_punctuation)
        s.last_smart_punctuation = 0;
      publish_mode(engine);
      return;
    }
    if (std::string(name) == "SmartPunctuationRepeat") {
      s.smart_punctuation_repeat = value == PROP_STATE_CHECKED;
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
    if (std::string(name).rfind("Scheme/", 0) == 0) {
      const bool japanese = std::string(name) == "Scheme/Japanese";
      if ((s.scheme_override && *s.scheme_override == "japanese") == japanese)
        return;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      if (japanese) {
        s.scheme_override = "japanese";
      } else {
        auto chinese = configured.at("preferences").value(
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
      s.punctuation_lock = selected;
      {
        const bool chinese = selected == "follow"
                                  ? configured.at("preferences").value("chinese_punctuation", true)
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
  guarded(engine, [&] {
    if (state(engine).session)
      apply(engine, msime_client_command(state(engine).session, MSIME_CANCEL));
    clear(engine);
  });
}
void content_type(IBusEngine *engine, guint purpose, guint hints) {
  guarded(engine, [&] {
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
  guarded(engine, [&] {
    if (mode_toggle) {
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      s.input_enabled = !s.input_enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, s.input_enabled));
      clear(engine);
      publish_mode(engine);
      handled = true;
      return;
    }
    s.open();
    if (!s.view.at("focused").get<bool>())
      apply(engine, msime_client_focus(s.session, true));
    if (s.chinese_punctuation && s.view.at("editing_text").get<std::string>().empty() &&
        (key == IBUS_quotedbl || key == IBUS_apostrophe)) {
      const char *pair = key == IBUS_quotedbl ? "“”" : "‘’";
      ibus_engine_commit_text(engine, ibus_text_new_from_string(pair));
      handled = true;
      return;
    }
    if ((flags & IBUS_CONTROL_MASK) && key == IBUS_period) {
      s.chinese_punctuation = !s.chinese_punctuation;
      s.view = response(msime_client_set_chinese_punctuation(
          s.session, s.chinese_punctuation));
      render(engine, s.view);
      publish_mode(engine);
      handled = true;
      return;
    }
    if (s.smart_punctuation_repeat && s.last_smart_punctuation == key &&
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
    if (!s.view.at("candidates").empty()) {
      auto edge = s.word_character.edge(key, (flags & IBUS_SHIFT_MASK) != 0);
      if (edge && s.view.at("local_mode") != "unknown" &&
          !s.view.at("editing_text").get<std::string>().empty()) {
        // Use the displayed highlighted candidate's generation and global
        // index. Engine owns Han extraction, including non-BMP characters.
        for (const auto &candidate : s.view.at("candidates")) {
          if (!candidate.at("highlighted").get<bool>())
            continue;
          auto id = candidate.at("id");
          handled =
              apply(engine, msime_client_select_edge(
                                s.session, id.at("generation").get<uint64_t>(),
                                id.at("index").get<size_t>(), *edge));
          if (!handled)
            handled = apply(engine, msime_client_punctuation(
                                        s.session, static_cast<uint8_t>(key)));
          return;
        }
      }
      auto navigation =
          s.navigation.command(key, (flags & IBUS_SHIFT_MASK) != 0);
      if (navigation) {
        handled = apply(engine, msime_client_command(s.session, *navigation));
        return;
      }
    }
    if (msime::linux_host::navigation_key(key)) {
      // Disabled bindings and empty candidate lists return native navigation
      // to the editor. Finish pending input before the editor moves focus.
      apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
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
  guarded(engine, [&] {
    auto &s = state(engine);
    if (!s.session || index >= s.view.at("candidates").size())
      return;
    auto id = s.view.at("candidates").at(index).at("id");
    apply(engine,
          msime_client_select(s.session, id.at("generation").get<uint64_t>(),
                              id.at("index").get<size_t>()));
  });
}
void page(IBusEngine *engine, uint32_t command) {
  guarded(engine, [&] {
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
  if (!s.focused || !s.session || s.preferences_loading)
    return G_SOURCE_CONTINUE;
  auto directory = configured.find("preferences_directory");
  if (directory == configured.end() || !directory->is_string())
    return G_SOURCE_CONTINUE;
  auto path = directory->get<std::string>();
  if (path.empty() || path.front() != '/')
    return G_SOURCE_CONTINUE;
  s.preferences_loading = true;
  auto task = g_task_new(
      engine, nullptr,
      +[](GObject *source, GAsyncResult *result, gpointer) {
        auto self = reinterpret_cast<MsimePreviewEngine *>(source);
        std::unique_ptr<char, decltype(&msime_client_string_free)> raw(
            static_cast<char *>(
                g_task_propagate_pointer(G_TASK(result), nullptr)),
            msime_client_string_free);
        // Explicit IBus destruction can precede completion of the worker.
        if (!self->state)
          return;
        auto &s = *self->state;
        s.preferences_loading = false;
        auto request = static_cast<PreferencesRead *>(
            g_task_get_task_data(G_TASK(result)));
        if (s.session != request->session || !s.focused || s.blocked)
          return;
        try {
          auto snapshot = response(raw.release());
          if (snapshot.is_null()) // Writer holds the shared store lock.
            return;
          if (s.private_input)
            snapshot["preferences"]["learning"] = false;
          auto bindings = msime::linux_host::NavigationBindings::read(
              snapshot.at("preferences"));
          auto edge_binding = msime::linux_host::WordCharacterBinding::read(
              snapshot.at("preferences"));
          auto encoded = snapshot.dump();
          auto updated = response(msime_client_update_preferences(
              s.session, reinterpret_cast<const uint8_t *>(encoded.data()),
              encoded.size()));
          s.view = updated.at("view");
          s.candidate_text_color =
              ::candidate_text_color(snapshot.at("preferences"));
          s.candidate_background_color =
              ::candidate_background_color(snapshot.at("preferences"));
          s.candidate_orientation =
              ::candidate_orientation(snapshot.at("preferences"));
          s.preedit_style = ::preedit_style(snapshot.at("preferences"));
          s.navigation = bindings;
          s.word_character = edge_binding;
          render(IBUS_ENGINE(source), s.view);
        } catch (...) {
          // Bad files and stale revisions preserve the live session. Retry on
          // the next tick without logging configuration, paths, or input.
        }
      },
      nullptr);
  g_task_set_task_data(
      task, new PreferencesRead{std::move(path), s.session},
      +[](gpointer p) { delete static_cast<PreferencesRead *>(p); });
  g_task_run_in_thread(
      task, +[](GTask *task, gpointer, gpointer data, GCancellable *) {
        const auto &path = static_cast<PreferencesRead *>(data)->directory;
        g_task_return_pointer(
            task,
            msime_client_try_load_preferences(
                reinterpret_cast<const uint8_t *>(path.data()), path.size()),
            +[](gpointer p) {
              msime_client_string_free(static_cast<char *>(p));
            });
      });
  g_object_unref(task);
  return G_SOURCE_CONTINUE;
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

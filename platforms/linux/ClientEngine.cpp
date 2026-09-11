#include "ClientEngine.h"
#include "VoiceWorker.h"
#include "msime_client.h"
#include <algorithm>
#include <memory>
#include <nlohmann/json.hpp>
#include <optional>
#include <tuple>
#include <stdexcept>

using Json = nlohmann::json;
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
struct State {
  MsimeVoiceWorker voice_worker;
  uint64_t session = 0;
  Json view;
  bool focused = false;
  bool blocked = false;
  bool private_input = false;
  bool input_enabled = true;
  bool chinese_punctuation = true;
  std::optional<bool> english_override;
  std::optional<bool> emoji_override;
  std::optional<bool> kaomoji_override;
  ~State() {
    voice_worker.cancel();
    close();
  }
  void close() {
    if (session)
      msime_client_string_free(msime_client_destroy(session));
    session = 0;
    view = nullptr;
  }
  void open() {
    if (session || blocked || !focused)
      return;
    auto options = configured;
    if (english_override)
      options["preferences"]["mixed_input"]["english"] = *english_override;
    if (emoji_override)
      options["preferences"]["mixed_input"]["emoji"] = *emoji_override;
    if (kaomoji_override)
      options["preferences"]["mixed_input"]["kaomoji"] = *kaomoji_override;
    if (private_input)
      options["preferences"]["learning"] = false;
    auto encoded = options.dump();
    view = response(msime_client_create(
        reinterpret_cast<const uint8_t *>(encoded.data()), encoded.size()));
    session = view.at("session").get<uint64_t>();
  }
};
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
  g_object_unref(property);
}
void publish_punctuation(IBusEngine *engine, bool enabled) {
  auto property = ibus_property_new(
      "ChinesePunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("启用中文标点转换"), TRUE, TRUE,
      enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_engine_update_property(engine, property);
  g_object_unref(property);
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
    g_object_unref(property);
  }
}
void render(IBusEngine *engine, const Json &view) {
  // Engine caret offsets refer to ASCII editing_text, never the display
  // preedit.
  auto text = view.at("editing_text").get<std::string>();
  const auto caret = view.at("caret_position").get<size_t>();
  if (caret > text.size() ||
      std::any_of(text.begin(), text.end(),
                  [](unsigned char c) { return c < 0x20 || c > 0x7e; }))
    throw std::runtime_error("Invalid editing text");
  ibus_engine_update_preedit_text_with_mode(
      engine, ibus_text_new_from_string(text.c_str()),
      static_cast<guint>(caret), !text.empty(), IBUS_ENGINE_PREEDIT_CLEAR);
  const auto &candidates = view.at("candidates");
  if (candidates.empty()) {
    ibus_engine_hide_lookup_table(engine);
    ibus_engine_hide_auxiliary_text(engine);
    return;
  }
  auto paging = std::to_string(view.at("page").get<size_t>() + 1) + "/" +
                std::to_string(view.at("page_count").get<size_t>()) +
                "  PgUp / PgDn";
  ibus_engine_update_auxiliary_text(
      engine, ibus_text_new_from_string(paging.c_str()), TRUE);
  auto table = ibus_lookup_table_new(static_cast<guint>(candidates.size()), 0,
                                     TRUE, FALSE);
  for (size_t index = 0; index < candidates.size(); ++index) {
    const auto &candidate = candidates.at(index);
    auto value = candidate.at("text").get<std::string>();
    ibus_lookup_table_append_candidate(
        table, ibus_text_new_from_string(value.c_str()));
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
    if (!text.empty())
      ibus_engine_commit_text(engine, ibus_text_new_from_string(text.c_str()));
  }
  state(engine).view = result.at("view");
  render(engine, state(engine).view);
  return result.at("handled").get<bool>();
}
template <class F> void guarded(IBusEngine *engine, F action) noexcept {
  try {
    action();
  } catch (...) {
    // Never log the raw error or response: either can include input or paths.
    g_warning("MSIME preview host operation failed");
    state(engine).close();
    clear(engine);
  }
}
void focus_in(IBusEngine *engine) {
  guarded(engine, [&] {
    auto &s = state(engine);
    register_properties(engine);
    s.focused = true;
    s.open();
    if (s.session)
      apply(engine, msime_client_focus(s.session, true));
  });
}
void focus_out(IBusEngine *engine) {
  guarded(engine, [&] {
    auto &s = state(engine);
    s.focused = false;
    if (s.session)
      apply(engine, msime_client_focus(s.session, false));
    clear(engine);
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
  });
}
bool modifier(guint key) {
  return (key >= IBUS_Shift_L && key <= IBUS_Hyper_R) || key == IBUS_Num_Lock ||
         key == IBUS_Scroll_Lock || key == IBUS_Mode_switch ||
         key == IBUS_ISO_Level3_Shift || key == IBUS_ISO_Level5_Shift;
}
gboolean process_key(IBusEngine *engine, guint key, guint, guint flags) {
  auto &s = state(engine);
  if (!s.focused || s.blocked || (flags & IBUS_RELEASE_MASK) || modifier(key))
    return FALSE;
  bool handled = false;
  guarded(engine, [&] {
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
    if (flags &
        (IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_MOD4_MASK | IBUS_SUPER_MASK |
         IBUS_META_MASK | IBUS_HYPER_MASK | IBUS_MOD5_MASK)) {
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
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
    case IBUS_Page_Up:
    case IBUS_KP_Page_Up:
      command = MSIME_PREVIOUS_PAGE;
      break;
    case IBUS_Page_Down:
    case IBUS_KP_Page_Down:
      command = MSIME_NEXT_PAGE;
      break;
    case IBUS_Up:
    case IBUS_KP_Up:
      command = MSIME_PREVIOUS_CANDIDATE;
      break;
    case IBUS_Down:
    case IBUS_KP_Down:
      command = MSIME_NEXT_CANDIDATE;
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
      handled = apply(
          engine, msime_client_character(s.session, static_cast<uint8_t>(key),
                                         (flags & IBUS_SHIFT_MASK) != 0));
    else
      apply(engine, msime_client_command(s.session, MSIME_CANCEL));
  });
  return handled;
}
void candidate_clicked(IBusEngine *engine, guint index, guint button,
                       guint flags) {
  if (button != 1 || flags || !state(engine).focused || state(engine).blocked)
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
    if (s.session && s.focused && !s.blocked)
      apply(engine, msime_client_command(s.session, command));
  });
}
void property_activate(IBusEngine *engine, const gchar *name, guint value) {
  if (!name || (std::string(name) != "InputEnabled" &&
       std::string(name) != "EnglishCandidates" &&
       std::string(name) != "EmojiCandidates" &&
       std::string(name) != "KaomojiCandidates" &&
       std::string(name) != "ChinesePunctuation") ||
      (value != PROP_STATE_CHECKED && value != PROP_STATE_UNCHECKED))
    return;
  guarded(engine, [&] {
    auto &s = state(engine);
    if (std::string(name) == "ChinesePunctuation") {
      s.chinese_punctuation = value == PROP_STATE_CHECKED;
      if (s.session)
        apply(engine, msime_client_set_chinese_punctuation(
                         s.session, s.chinese_punctuation));
      publish_punctuation(engine, s.chinese_punctuation);
      return;
    }
    if (std::string(name) == "EnglishCandidates" ||
        std::string(name) == "EmojiCandidates" ||
        std::string(name) == "KaomojiCandidates") {
      const bool enabled = value == PROP_STATE_CHECKED;
      if (s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
      s.close();
      if (std::string(name) == "EnglishCandidates")
        s.english_override = enabled;
      else if (std::string(name) == "EmojiCandidates")
        s.emoji_override = enabled;
      else
        s.kaomoji_override = enabled;
      s.open();
      if (s.session)
        apply(engine, msime_client_focus(s.session, true));
      clear(engine);
      publish_expressive(engine, s);
      return;
    }
    s.input_enabled = value == PROP_STATE_CHECKED;
    if (s.session)
      apply(engine, msime_client_focus(s.session, s.input_enabled));
    clear(engine);
    publish_input_enabled(engine, s.input_enabled);
  });
}
void register_properties(IBusEngine *engine) {
  auto properties = ibus_prop_list_new();
  auto property = ibus_property_new(
      "InputEnabled", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("输入启用"), "",
      ibus_text_new_from_static_string("启用或停用当前 Linux 输入会话"), TRUE,
      TRUE, PROP_STATE_CHECKED, nullptr);
  ibus_prop_list_append(properties, property);
  auto punctuation = ibus_property_new(
      "ChinesePunctuation", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("中文标点"), "",
      ibus_text_new_from_static_string("启用中文标点转换"), TRUE, TRUE,
      PROP_STATE_CHECKED, nullptr);
  ibus_prop_list_append(properties, punctuation);
  g_object_unref(punctuation);
  auto english = ibus_property_new(
      "EnglishCandidates", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("英文候选"), "",
      ibus_text_new_from_static_string("在中文方案中补充英文候选"), TRUE, TRUE,
      configured.at("preferences").value("mixed_input", Json::object()).value("english", true)
          ? PROP_STATE_CHECKED
          : PROP_STATE_UNCHECKED,
      nullptr);
  ibus_prop_list_append(properties, english);
  g_object_unref(english);
  for (const auto &[name, label, key] : {
           std::tuple<const char *, const char *, const char *>{"EmojiCandidates", "Emoji候选", "emoji"},
           {"KaomojiCandidates", "颜文字候选", "kaomoji"}}) {
    auto item = ibus_property_new(
        name, PROP_TYPE_TOGGLE, ibus_text_new_from_string(label), "",
        ibus_text_new_from_static_string("在中文方案中补充表达候选"), TRUE, TRUE,
        configured.at("preferences").value("mixed_input", Json::object()).value(key, false)
            ? PROP_STATE_CHECKED
            : PROP_STATE_UNCHECKED,
        nullptr);
    ibus_prop_list_append(properties, item);
    g_object_unref(item);
  }
  ibus_engine_register_properties(engine, properties);
  g_object_unref(property);
  g_object_unref(properties);
}
void destroy(IBusObject *object) {
  auto self = reinterpret_cast<MsimePreviewEngine *>(object);
  delete self->state;
  self->state = nullptr;
  IBUS_OBJECT_CLASS(msime_preview_engine_parent_class)->destroy(object);
}
} // namespace

static void msime_preview_engine_init(MsimePreviewEngine *engine) {
  engine->state = new State();
}
static void msime_preview_engine_class_init(MsimePreviewEngineClass *klass) {
  auto engine = IBUS_ENGINE_CLASS(klass);
  engine->process_key_event = process_key;
  engine->focus_in = focus_in;
  engine->focus_out = focus_out;
  engine->disable = focus_out;
  engine->reset = reset;
  engine->set_content_type = content_type;
  engine->candidate_clicked = candidate_clicked;
  engine->property_activate = property_activate;
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

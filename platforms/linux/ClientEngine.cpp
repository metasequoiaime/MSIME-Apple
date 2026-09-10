#include "ClientEngine.h"
#include "NavigationBindings.h"
#include "WordCharacterBinding.h"
#include "msime_client.h"
#include <algorithm>
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>

using Json = nlohmann::json;
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
struct State {
  uint64_t session = 0;
  Json view;
  bool focused = false;
  bool blocked = false;
  bool private_input = false;
  bool input_enabled = true;
  guint preferences_timer = 0;
  bool preferences_loading = false;
  msime::linux_host::NavigationBindings navigation;
  msime::linux_host::WordCharacterBinding word_character;
  ~State() { close(); }
  void close() {
    if (session)
      msime_client_string_free(msime_client_destroy(session));
    session = 0;
    view = nullptr;
  }
  void open() {
    if (session || blocked || !focused || !input_enabled)
      return;
    auto options = configured;
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
    navigation = bindings;
    word_character = edge_binding;
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
void publish_mode(IBusEngine *engine, bool registration = false) {
  const auto &s = state(engine);
  auto property = ibus_property_new(
      "InputMode", PROP_TYPE_TOGGLE,
      ibus_text_new_from_static_string("输入法模式"), "",
      ibus_text_new_from_static_string(s.input_enabled ? "使用当前输入方案"
                                                       : "直接输入（不转换）"),
      s.focused && !s.blocked, TRUE,
      s.input_enabled ? PROP_STATE_CHECKED : PROP_STATE_UNCHECKED, nullptr);
  ibus_property_set_symbol(
      property, ibus_text_new_from_static_string(s.input_enabled ? "文" : "A"));
  if (registration) {
    auto properties = ibus_prop_list_new();
    ibus_prop_list_append(properties, property);
    ibus_engine_register_properties(engine, properties);
  } else {
    ibus_engine_update_property(engine, property);
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
                std::to_string(view.at("page_count").get<size_t>());
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
  if (!name || std::string(name) != "InputMode" || !s.focused || s.blocked ||
      (value != PROP_STATE_CHECKED && value != PROP_STATE_UNCHECKED))
    return;
  guarded(engine, [&] {
    const bool enabled = value == PROP_STATE_CHECKED;
    if (enabled != s.input_enabled) {
      if (!enabled && s.session)
        apply(engine, msime_client_command(s.session, MSIME_FINISH_COMPOSITION));
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
  if (!s.focused || s.blocked || !s.input_enabled ||
      (flags & IBUS_RELEASE_MASK) || modifier(key))
    return FALSE;
  bool handled = false;
  guarded(engine, [&] {
    s.open();
    if (!s.view.at("focused").get<bool>())
      apply(engine, msime_client_focus(s.session, true));
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
          auto edge_binding = msime::linux_host::WordCharacterBinding::read(snapshot.at("preferences"));
          auto encoded = snapshot.dump();
          auto updated = response(msime_client_update_preferences(
              s.session, reinterpret_cast<const uint8_t *>(encoded.data()),
              encoded.size()));
          s.view = updated.at("view");
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

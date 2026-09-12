#include "ClientEngine.h"
#include "msime_client.h"
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <sys/file.h>
#include <unistd.h>
#include <vector>

namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
struct Observation {
  std::string committed;
  std::string preedit;
  std::string auxiliary;
  std::vector<std::string> candidates;
  std::vector<std::string> labels;
  guint first_candidate_color = 0;
  bool lookup_visible = false;
  bool preedit_visible = false;
  guint cursor = 0;
  bool mode_registered = false;
  bool input_enabled = false;
  bool english_mode = false;
  bool mode_sensitive = false;
  bool punctuation_enabled = false;
};
void signal(GDBusConnection *, const gchar *, const gchar *, const gchar *,
            const gchar *name, GVariant *parameters, gpointer data) {
  auto &seen = *static_cast<Observation *>(data);
  if (std::string(name) == "HidePreeditText") {
    seen.preedit_visible = false;
    return;
  }
  if (std::string(name) == "HideLookupTable") {
    seen.lookup_visible = false;
    return;
  }
  if (std::string(name) == "HideAuxiliaryText") {
    seen.auxiliary.clear();
    return;
  }
  if (std::string(name) != "CommitText" &&
      std::string(name) != "UpdatePreeditText" &&
      std::string(name) != "UpdateLookupTable" &&
      std::string(name) != "UpdateAuxiliaryText" &&
      std::string(name) != "RegisterProperties" &&
      std::string(name) != "UpdateProperty")
    return;
  GVariant *encoded = g_variant_get_child_value(parameters, 0);
  auto object = ibus_serializable_deserialize(encoded);
  g_variant_unref(encoded);
  if (!object)
    std::abort();
  g_object_ref_sink(object);
  if (std::string(name) == "UpdateAuxiliaryText")
    seen.auxiliary = ibus_text_get_text(IBUS_TEXT(object));
  auto observe_property = [&](IBusProperty *property) {
    if (std::string(ibus_property_get_key(property)) == "InputMode") {
      seen.input_enabled =
          ibus_property_get_state(property) == PROP_STATE_CHECKED;
      seen.mode_sensitive = ibus_property_get_sensitive(property);
    }
    if (std::string(ibus_property_get_key(property)) == "EnglishMode")
      seen.english_mode = ibus_property_get_state(property) == PROP_STATE_CHECKED;
    if (std::string(ibus_property_get_key(property)) == "Punctuation")
      seen.punctuation_enabled =
          ibus_property_get_state(property) == PROP_STATE_CHECKED;
  };
  if (std::string(name) == "RegisterProperties") {
    auto properties = IBUS_PROP_LIST(object);
    for (guint i = 0; auto property = ibus_prop_list_get(properties, i); ++i) {
      observe_property(property);
      if (std::string(ibus_property_get_key(property)) == "InputMode")
        seen.mode_registered = true;
    }
  }
  if (std::string(name) == "UpdateProperty")
    observe_property(IBUS_PROPERTY(object));
  if (std::string(name) == "CommitText")
    seen.committed += ibus_text_get_text(IBUS_TEXT(object));
  if (std::string(name) == "UpdatePreeditText") {
    seen.preedit = ibus_text_get_text(IBUS_TEXT(object));
    gboolean visible;
    g_variant_get_child(parameters, 2, "b", &visible);
    seen.preedit_visible = visible;
  }
  if (std::string(name) == "UpdateLookupTable") {
    seen.candidates.clear();
    seen.labels.clear();
    auto table = IBUS_LOOKUP_TABLE(object);
    seen.cursor = ibus_lookup_table_get_cursor_pos(table);
    for (guint i = 0; i < ibus_lookup_table_get_number_of_candidates(table);
         ++i) {
      seen.candidates.emplace_back(
          ibus_text_get_text(ibus_lookup_table_get_candidate(table, i)));
      seen.labels.emplace_back(
          ibus_text_get_text(ibus_lookup_table_get_label(table, i)));
    }
    if (ibus_lookup_table_get_number_of_candidates(table) != 0) {
      auto text = ibus_lookup_table_get_candidate(table, 0);
      auto attributes = ibus_text_get_attributes(text);
      if (auto attribute = ibus_attr_list_get(attributes, 0))
        seen.first_candidate_color = ibus_attribute_get_value(attribute);
    }
    gboolean visible;
    g_variant_get_child(parameters, 1, "b", &visible);
    seen.lookup_visible = visible;
  }
  g_object_unref(object);
}
struct Call {
  bool done = false;
  GVariant *result = nullptr;
  GError *error = nullptr;
};
GVariant *call(GDBusConnection *connection, const char *destination,
               const char *method, GVariant *parameters) {
  Call pending;
  const char *interface = std::string(method) == "Set"
                              ? "org.freedesktop.DBus.Properties"
                              : "org.freedesktop.IBus.Engine";
  g_dbus_connection_call(
      connection, destination, "/app/msime/test/engine", interface, method,
      parameters, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr,
      +[](GObject *source, GAsyncResult *result, gpointer data) {
        auto &p = *static_cast<Call *>(data);
        p.result = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source),
                                                 result, &p.error);
        p.done = true;
      },
      &pending);
  while (!pending.done)
    g_main_context_iteration(nullptr, TRUE);
  if (pending.error) {
    // This connection carries only the isolated synthetic test fixture.
    std::string message = std::string(method) + ": " + pending.error->message;
    g_error_free(pending.error);
    throw std::runtime_error(message);
  }
  while (g_main_context_iteration(nullptr, FALSE)) {
  }
  return pending.result;
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2)
    return 2;
  try {
    // This fixture asserts RegisterProperties and must exercise the real menu path.
    g_unsetenv("MSIME_DISABLE_IBUS_PROPERTIES");
    // Synthetic fixture only; the production host does not invoke this
    // bootstrap.
    gchar *temporary = g_dir_make_tmp("msime-ibus-test-XXXXXX", nullptr);
    require(temporary != nullptr, "Cannot create test directory");
    std::filesystem::path root(temporary);
    g_free(temporary);
    struct Cleanup {
      std::filesystem::path path;
      ~Cleanup() {
        std::error_code error;
        std::filesystem::remove_all(path, error);
      }
    } cleanup{root};
    auto bootstrap = nlohmann::json{
        {"resources", argv[1]},
        {"state_root",
         root.string()}}.dump();
    std::unique_ptr<char, decltype(&msime_client_string_free)> prepared(
        msime_client_prepare_host(
            reinterpret_cast<const uint8_t *>(bootstrap.data()),
            bootstrap.size()),
        msime_client_string_free);
    auto result = nlohmann::json::parse(prepared.get());
    require(result.at("ok").get<bool>(), "Locked dictionary bootstrap failed");
    auto options = result.at("value");
    options["preferences"]["learning"] = false;
    options["preferences"]["keybindings"]["switch_language_ctrl"] = true;
    options["preferences"]["candidate_text_color"] = "#123456";
    options["preferences"]["candidate_page_size"] = 2;
    std::ofstream(root / "preferences.json") << nlohmann::json{
        {"format_version", 1},
        {"revision", 0},
        {"preferences", options.at("preferences")}}.dump();
    msime_preview_configure(options.dump());
    ibus_init();
    auto bus = g_test_dbus_new(G_TEST_DBUS_NONE);
    g_test_dbus_up(bus);
    auto connect = [&] {
      return g_dbus_connection_new_for_address_sync(
          g_test_dbus_get_bus_address(bus),
          static_cast<GDBusConnectionFlags>(
              G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
              G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
          nullptr, nullptr, nullptr);
    };
    auto server = connect();
    auto client = connect();
    require(server && client, "Private D-Bus unavailable");
    auto engine = IBUS_ENGINE(
        g_object_new(msime_preview_engine_get_type(), "engine-name",
                     "msime-client-preview", "object-path",
                     "/app/msime/test/engine", "connection", server, nullptr));
    g_object_ref_sink(engine);
    Observation seen;
    const char *destination = g_dbus_connection_get_unique_name(server);
    guint subscription = g_dbus_connection_signal_subscribe(
        client, destination, "org.freedesktop.IBus.Engine", nullptr,
        "/app/msime/test/engine", nullptr, G_DBUS_SIGNAL_FLAGS_NONE, signal,
        &seen, nullptr);
    auto invoke = [&](const char *method, GVariant *params = nullptr) {
      auto value = call(client, destination, method, params);
      g_variant_unref(value);
    };
    auto key = [&](guint value, guint flags = 0) {
      auto reply = call(client, destination, "ProcessKeyEvent",
                        g_variant_new("(uuu)", value, 0, flags));
      gboolean handled;
      g_variant_get(reply, "(b)", &handled);
      g_variant_unref(reply);
      return handled != FALSE;
    };
    auto phrase = [&] {
      for (char c : std::string("nihao"))
        require(key(c), "Phrase key not consumed");
    };
    invoke("FocusIn");
    require(seen.mode_registered && seen.input_enabled && seen.mode_sensitive,
            "Input mode property was not registered");
    invoke("PropertyActivate",
           g_variant_new("(su)", "CharacterMode", PROP_STATE_CHECKED));
    invoke("PropertyActivate",
           g_variant_new("(su)", "CharacterMode", PROP_STATE_UNCHECKED));
    require(seen.punctuation_enabled, "Chinese punctuation was not enabled");
    invoke("PropertyActivate",
           g_variant_new("(su)", "PunctuationLock/english", PROP_STATE_CHECKED));
    invoke("PropertyActivate",
           g_variant_new("(su)", "PunctuationLock/follow", PROP_STATE_CHECKED));
    auto mode = [&](guint value) {
      invoke("PropertyActivate", g_variant_new("(su)", "InputMode", value));
    };
    require(key(IBUS_e, IBUS_CONTROL_MASK | IBUS_SHIFT_MASK),
            "Ctrl+Shift+E was not consumed");
    require(seen.english_mode && seen.input_enabled, "Ctrl+Shift+E did not enter dedicated English mode");
    require(key(IBUS_e, IBUS_CONTROL_MASK | IBUS_SHIFT_MASK),
            "Ctrl+Shift+E could not restore the input mode");
    require(!seen.english_mode && seen.input_enabled, "Ctrl+Shift+E did not restore Chinese mode");
    require(key(IBUS_space, IBUS_CONTROL_MASK | IBUS_MOD1_MASK),
            "Ctrl+Alt+Space was not consumed");
    require(!seen.input_enabled, "Ctrl+Alt+Space did not enter English mode");
    require(key(IBUS_space, IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_RELEASE_MASK),
            "Ctrl+Alt+Space release was not consumed");
    require(key(IBUS_space, IBUS_CONTROL_MASK | IBUS_MOD1_MASK),
            "Ctrl+Alt+Space could not restore input mode");
    require(seen.input_enabled, "Ctrl+Alt+Space did not restore input mode");
    require(key(IBUS_space, IBUS_CONTROL_MASK | IBUS_MOD1_MASK | IBUS_RELEASE_MASK),
            "Ctrl+Alt+Space restore release was not consumed");
    require(key(IBUS_space, IBUS_CONTROL_MASK), "Ctrl+Space was not consumed");
    require(!seen.input_enabled, "Ctrl+Space did not enter English mode");
    require(key(IBUS_space, IBUS_CONTROL_MASK),
            "Ctrl+Space could not restore input mode");
    require(seen.input_enabled, "Ctrl+Space did not restore input mode");
    // Modifier chords must never be mistaken for a bare Ctrl/Shift release.
    for (bool ctrl_first : {true, false}) {
      for (bool ctrl_release_first : {true, false}) {
        const guint first = ctrl_first ? IBUS_Control_L : IBUS_Shift_L;
        const guint second = ctrl_first ? IBUS_Shift_L : IBUS_Control_L;
        const guint first_mask = ctrl_first ? IBUS_CONTROL_MASK : IBUS_SHIFT_MASK;
        require(!key(first, first_mask), "Modifier press was intercepted");
        require(!key(second, IBUS_CONTROL_MASK | IBUS_SHIFT_MASK),
                "Modifier chord press was intercepted");
        const guint released = ctrl_release_first ? IBUS_Control_L : IBUS_Shift_L;
        const guint remaining = ctrl_release_first ? IBUS_Shift_L : IBUS_Control_L;
        const guint remaining_mask = ctrl_release_first ? IBUS_SHIFT_MASK : IBUS_CONTROL_MASK;
        require(!key(released, IBUS_RELEASE_MASK | IBUS_CONTROL_MASK | IBUS_SHIFT_MASK),
                "Modifier chord release toggled input");
        require(!key(remaining, IBUS_RELEASE_MASK | remaining_mask) && seen.input_enabled,
                "Modifier chord tail toggled input");
      }
    }
    for (guint modifier_key : {IBUS_Control_L, IBUS_Shift_L}) {
      require(!key(modifier_key), "Bare modifier press was intercepted");
      require(key(modifier_key, IBUS_RELEASE_MASK) && !seen.input_enabled,
              "Bare modifier no longer disabled input");
      require(!key(modifier_key), "Bare modifier restore press was intercepted");
      require(key(modifier_key, IBUS_RELEASE_MASK) && seen.input_enabled,
              "Bare modifier no longer restored input");
    }
    require(seen.committed.empty(), "Mode setup unexpectedly committed text");
    phrase();
    require(seen.committed.empty(), "Phrase unexpectedly committed before selection");
    require(key(IBUS_period, IBUS_CONTROL_MASK),
            "Ctrl+. punctuation toggle was not consumed");
    require(!seen.punctuation_enabled,
            "Ctrl+. did not toggle punctuation state");
    require(key(IBUS_period, IBUS_CONTROL_MASK),
            "Ctrl+. punctuation restore was not consumed");
    require(seen.punctuation_enabled,
            "Ctrl+. did not restore punctuation state");
    require(seen.committed.empty(), "Punctuation toggle unexpectedly committed text");
    invoke("CursorDown");
    require(seen.committed.empty(), "CursorDown unexpectedly committed text");
    auto mode_commit = seen.candidates.at(seen.cursor);
    mode(PROP_STATE_UNCHECKED);
    require(!seen.input_enabled, "Direct mode remained enabled");
    require(seen.committed == mode_commit, "Direct mode lost highlighted composition");
    require(!seen.preedit_visible, "Direct mode left preedit visible");
    require(!seen.lookup_visible, "Direct mode left candidates visible");
    mode(PROP_STATE_UNCHECKED);
    require(seen.committed == mode_commit,
            "Repeated mode request committed twice");
    for (guint direct :
         std::vector<guint>{'n', ',', '1', IBUS_space, IBUS_Tab, IBUS_Down})
      require(!key(direct), "Direct input mode consumed an editor key");
    invoke("CandidateClicked", g_variant_new("(uuu)", 0, 1, 0));
    invoke("PageDown");
    require(seen.committed == mode_commit && !seen.lookup_visible,
            "Stale panel action modified direct input");
    invoke("FocusOut");
    mode(PROP_STATE_CHECKED);
    require(!seen.input_enabled && !seen.mode_sensitive,
            "Unfocused mode activation was accepted");
    invoke("FocusIn");
    require(!seen.input_enabled && !key('n'), "Focus reset direct input mode");
    mode(PROP_STATE_INCONSISTENT);
    invoke("PropertyActivate",
           g_variant_new("(su)", "Unknown", PROP_STATE_CHECKED));
    require(!seen.input_enabled, "Invalid property activation changed mode");
    mode(PROP_STATE_CHECKED);
    require(seen.input_enabled, "Input mode did not recover");
    seen.committed.clear();
    // A visible incremental candidate list must not turn editing into cancel
    // or make Enter select a candidate instead of committing raw spelling.
    phrase();
    require(key(IBUS_BackSpace) && seen.preedit == "niha" &&
                seen.preedit_visible && seen.committed.empty(),
            "Backspace cancelled incremental composition instead of deleting one key");
    invoke("Reset");
    for (guint delete_key : {IBUS_Delete, IBUS_KP_Delete}) {
      phrase();
      require(key(IBUS_Left) && key(delete_key) && seen.preedit == "niha" &&
                  seen.preedit_visible && seen.committed.empty(),
              "Forward delete cancelled incremental composition instead of editing at caret");
      invoke("Reset");
    }
    for (guint enter_key : {IBUS_Return, IBUS_KP_Enter}) {
      phrase();
      require(key(enter_key) && seen.committed == "nihao" &&
                  !seen.preedit_visible && !seen.lookup_visible,
              "Enter selected an incremental candidate instead of raw spelling");
      seen.committed.clear();
    }
    for (guint idle_key : {IBUS_BackSpace, IBUS_Delete, IBUS_KP_Delete,
                           IBUS_Return, IBUS_KP_Enter})
      require(!key(idle_key) && seen.committed.empty(),
              "Idle composition edit key was intercepted");
    phrase();
    require(seen.preedit_visible && seen.preedit == "nihao",
            "Preedit signal missing");
    require(seen.lookup_visible && seen.candidates.size() == 2 &&
                seen.candidates[0] == "你好",
            "Candidate signal mismatch");
    require(!seen.labels.empty() && seen.labels.front().rfind("1", 0) == 0,
            "Candidate numeric label missing");
    require(seen.first_candidate_color == 0x123456,
            "Candidate text color attribute missing");
    require(!key(IBUS_Shift_L) && !key('n', IBUS_RELEASE_MASK),
            "Modifier/release was consumed");
    require(seen.preedit == "nihao", "Modifier/release canceled composition");
    require(key(IBUS_space), "Space not handled");
    require(seen.committed == "你好" && !seen.preedit_visible &&
                !seen.lookup_visible,
            "Commit/clear signal mismatch");
    require(!key(IBUS_Shift_L) && key(IBUS_Shift_L, IBUS_RELEASE_MASK),
            "Pure Shift did not toggle input mode off");
    require(!seen.input_enabled, "Pure Shift did not enter direct mode");
    require(!key(IBUS_Shift_L) && key(IBUS_Shift_L, IBUS_RELEASE_MASK),
            "Pure Shift did not toggle input mode on");
    require(seen.input_enabled, "Pure Shift did not restore input mode");
    phrase();
    require(key(IBUS_End), "End did not move to the page edge");
    require(key(IBUS_Home), "Home did not move to the page edge");
    invoke("PageDown");
    require(seen.lookup_visible && !seen.candidates.empty(),
            "Shared next page missing");
    auto selected = seen.candidates.front();
    invoke("CandidateClicked", g_variant_new("(uuu)", 0, 1, 0));
    require(seen.committed == "你好" + selected,
            "Candidate click did not use shared global index");
    invoke("Reset");
    require(key(','), "Punctuation not consumed");
    require(seen.committed == "你好" + selected + "，",
            "Chinese punctuation not applied");
    require(key(IBUS_quotedbl), "Paired quote was not consumed");
    require(seen.committed == "你好" + selected + "，“”",
            "Paired quote output mismatch");
    invoke("Reset");
    require(key('u', IBUS_SHIFT_MASK), "Shift+U Unicode mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "U",
            "Shift+U did not enter Unicode mode");
    require(key(IBUS_Escape), "Unicode mode could not be canceled");
    require(key('t', IBUS_SHIFT_MASK), "Shift+T date-time mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "T",
            "Shift+T did not enter date-time mode");
    require(key(IBUS_Escape), "Date-time mode could not be canceled");
    require(key('k', IBUS_SHIFT_MASK), "Shift+K quick-phrase mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "K",
            "Shift+K did not enter quick-phrase mode");
    require(key(IBUS_Escape), "Quick-phrase mode could not be canceled");
    require(key('e', IBUS_SHIFT_MASK), "Shift+E emoji mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "E",
            "Shift+E did not enter emoji mode");
    require(key(IBUS_Escape), "Emoji mode could not be canceled");
    require(key('m', IBUS_SHIFT_MASK), "Shift+M kaomoji mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "M",
            "Shift+M did not enter kaomoji mode");
    require(key(IBUS_Escape), "Kaomoji mode could not be canceled");
    require(key('j', IBUS_SHIFT_MASK), "Shift+J super-jianpin mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "J",
            "Shift+J did not enter super-jianpin mode");
    require(key(IBUS_Escape), "Super-jianpin mode could not be canceled");
    require(key('y', IBUS_SHIFT_MASK), "Shift+Y temporary English mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "Y",
            "Shift+Y did not enter temporary English mode");
    require(key(IBUS_Escape), "Temporary English mode could not be canceled");
    require(key('r', IBUS_SHIFT_MASK), "Shift+R temporary Japanese mode was not consumed");
    require(seen.preedit_visible && seen.preedit == "R",
            "Shift+R did not enter temporary Japanese mode");
    require(key(IBUS_Escape), "Temporary Japanese mode could not be canceled");
    invoke("Reset");
    invoke("PropertyActivate",
           g_variant_new("(su)", "Scheme/Japanese", PROP_STATE_CHECKED));
    require(key('a'), "Japanese scheme did not consume Romaji input");
    require(seen.lookup_visible && !seen.candidates.empty() &&
                seen.candidates.front().find("あ") != std::string::npos,
            "Japanese scheme menu did not switch the Engine");
    invoke("Reset");
    invoke("PropertyActivate",
           g_variant_new("(su)", "Scheme/Chinese", PROP_STATE_CHECKED));
    invoke("PropertyActivate",
           g_variant_new("(su)", "Scheme/Wubi", PROP_STATE_CHECKED));
    require(key('a'), "Explicit Wubi scheme did not switch the Engine");
    invoke("Reset");
    invoke("PropertyActivate",
           g_variant_new("(su)", "Scheme/Quanpin", PROP_STATE_CHECKED));
    auto committed = seen.committed;
    phrase();
    invoke("PropertyActivate",
           g_variant_new("(su)", "ChinesePunctuation", PROP_STATE_UNCHECKED));
    require(seen.preedit_visible && seen.preedit == "nihao" &&
                seen.lookup_visible && seen.committed == committed,
            "Punctuation toggle lost composition or committed input");
    invoke("Reset");
    require(!key(','), "English punctuation should pass through when idle");
    require(seen.committed == committed, "English punctuation emitted a commit");
    invoke("PropertyActivate",
           g_variant_new("(su)", "ChinesePunctuation", PROP_STATE_CHECKED));
    require(key(','), "Restored Chinese punctuation was not consumed");
    require(seen.committed == committed + "，",
            "Restored punctuation mode did not reach the session");
    committed = seen.committed;
    phrase();
    require(key(IBUS_KP_Page_Down), "Keypad paging not consumed");
    auto numbered = seen.candidates.front();
    require(key(IBUS_KP_1) && seen.committed == committed + numbered,
            "Keypad digit did not select the shared page");
    invoke("Reset");
    committed = seen.committed;
    phrase();
    require(!key('c', IBUS_CONTROL_MASK) && !seen.preedit_visible,
            "Shortcut was intercepted or left stale composition");
    require(seen.committed == committed,
            "Shortcut unexpectedly committed input");
    require(key(IBUS_space, IBUS_CONTROL_MASK),
            "Control-space toggle was not handled");
    require(!key('n'), "Disabled input consumed a character");
    invoke("PropertyActivate",
           g_variant_new("(su)", "InputEnabled", PROP_STATE_CHECKED));
    require(key('n'), "InputEnabled property did not re-enable input");
    invoke("Reset");
    require(key(IBUS_space, IBUS_CONTROL_MASK),
            "Control-space disable was not handled");
    require(!key('n'), "Disabled input consumed a character after property toggle");
    require(key(IBUS_space, IBUS_CONTROL_MASK),
            "Control-space re-enable was not handled");
    require(key('n'), "Re-enabled input did not consume a character");
    invoke("Reset");
    invoke("Reset");
    invoke("FocusOut");
    require(!seen.preedit_visible && !seen.lookup_visible && !key('n'),
            "Focus loss did not clear and stop input");
    invoke("Set", g_variant_new(
                      "(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                      g_variant_new("(uu)", IBUS_INPUT_PURPOSE_PASSWORD, 0)));
    invoke("FocusIn");
    require(!seen.mode_sensitive, "Password field exposed a mode switch");
    mode(PROP_STATE_UNCHECKED);
    require(seen.input_enabled, "Password field accepted a mode change");
    require(!key('n') && !seen.preedit_visible && seen.committed == committed,
            "Password input reached engine");
    invoke("Set",
           g_variant_new("(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                         g_variant_new("(uu)", IBUS_INPUT_PURPOSE_FREE_FORM,
                                       IBUS_INPUT_HINT_PRIVATE)));
    phrase();
    require(key(IBUS_space) && seen.committed == committed + "你好",
            "Private text focus did not recover");
    invoke("FocusOut");
    invoke("FocusIn");
    invoke("PropertyActivate", g_variant_new("(su)", "CharacterWidth", 1));
    require(key('1'), "Fullwidth idle digit was not handled");
    require(seen.committed == committed + "你好１", "Fullwidth ASCII commit mismatch");
    invoke("PropertyActivate", g_variant_new("(su)", "CharacterWidth", 0));
    require(!key('2'), "Halfwidth idle digit was intercepted");
    require(seen.committed == committed + "你好１", "Halfwidth ASCII commit mismatch");
    auto settle = [&] {
      const auto deadline = g_get_monotonic_time() + 2200000;
      while (g_get_monotonic_time() < deadline) {
        while (g_main_context_iteration(nullptr, FALSE)) {}
        g_usleep(1000);
      }
    };
    auto save = [&](uint64_t revision, size_t page_size) {
      auto preferences = options.at("preferences");
      preferences["candidate_page_size"] = page_size;
      preferences["learning"] = true;
      preferences["frequency"]["mode"] = "pin";
      preferences["frequency"]["trigger_count"] = 1;
      preferences["candidate_text_color"] = "#abcdef";
      auto snapshot = nlohmann::json{{"format_version", 1},
                                     {"revision", revision},
                                     {"preferences", preferences}};
      std::ofstream(root / "preferences.next") << snapshot.dump();
      std::filesystem::rename(root / "preferences.next", root / "preferences.json");
    };
    phrase();
    save(1, 3);
    settle();
    require(seen.preedit == "nihao" && seen.candidates.size() == 2,
            "Preferences interrupted the active composition");
    invoke("Reset");
    phrase();
    require(seen.candidates.size() == 3,
            "Deferred preferences did not apply after reset");
    require(seen.first_candidate_color == 0xabcdef,
            "Reloaded candidate text color did not apply");
    std::ofstream(root / "preferences.json") << "invalid";
    settle();
    require(seen.preedit == "nihao" && seen.candidates.size() == 3,
            "Malformed preferences disturbed composition");
    invoke("Reset");
    save(0, 4);
    settle();
    phrase();
    require(seen.candidates.size() == 3,
            "Stale revision replaced live settings");
    invoke("Reset");
    int lock =
        open((root / "preferences.lock").c_str(), O_CREAT | O_RDWR, 0600);
    require(lock >= 0 && flock(lock, LOCK_EX | LOCK_NB) == 0,
            "Cannot lock synthetic preferences");
    save(2, 4);
    settle();
    phrase();
    require(seen.candidates.size() == 3, "Reader ignored the writer lock");
    invoke("Reset");
    flock(lock, LOCK_UN);
    close(lock);
    settle();
    phrase();
    require(seen.candidates.size() == 4,
            "Settings did not recover after writer unlock");
    auto private_candidates = seen.candidates;
    invoke("CandidateClicked", g_variant_new("(uuu)", 1, 1, 0));
    phrase();
    require(seen.candidates == private_candidates,
            "Reload enabled frequency learning in a private session");
    invoke("Reset");
    invoke("Set",
           g_variant_new("(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                         g_variant_new("(uu)", IBUS_INPUT_PURPOSE_FREE_FORM, 0)));
    settle();
    phrase();
    auto learned = seen.candidates.at(1);
    invoke("CandidateClicked", g_variant_new("(uuu)", 1, 1, 0));
    phrase();
    require(seen.candidates.front() == learned,
            "Normal session did not restore configured frequency learning");
    invoke("Reset");
    struct Binding {
      const char *name;
      guint next;
      guint previous;
      bool candidate;
    };
    const std::vector<Binding> bindings = {
        {"minus_equal", IBUS_equal, IBUS_minus, false},
        {"comma_period", IBUS_period, IBUS_comma, false},
        {"brackets", IBUS_bracketright, IBUS_bracketleft, false},
        {"tab", IBUS_Tab, IBUS_ISO_Left_Tab, false},
        {"page_up_down", IBUS_KP_Page_Down, IBUS_KP_Page_Up, false},
        {"arrows", IBUS_KP_Down, IBUS_KP_Up, true}};
    uint64_t revision = 3;
    for (const auto &binding : bindings) {
      for (const auto &item : bindings)
        options["preferences"]["navigation"][item.name] = false;
      options["preferences"]["navigation"][binding.name] = true;
      phrase();
      auto first_page = seen.candidates;
      auto before_commit = seen.committed;
      save(revision++, 4);
      settle();
      require(seen.preedit == "nihao", "Binding update canceled composition");
      require(key(binding.next), "Configured forward binding was not handled");
      require(binding.candidate ? seen.cursor == 1
                                : seen.candidates != first_page,
              "Configured forward binding did not move candidates");
      require(key(binding.previous,
                  binding.previous == IBUS_ISO_Left_Tab ? IBUS_SHIFT_MASK : 0),
              "Configured backward binding was not handled");
      require(
          seen.candidates == first_page && seen.cursor == 0 &&
              seen.committed == before_commit,
          "Navigation changed input or failed to return to first candidate");
      invoke("Reset");
    }
    for (const auto &binding : bindings)
      options["preferences"]["navigation"][binding.name] = false;
    save(revision++, 4);
    settle();
    for (guint native_key : {IBUS_Tab, IBUS_ISO_Left_Tab, IBUS_Page_Down,
                             IBUS_Page_Up, IBUS_Down, IBUS_Up}) {
      require(!key(native_key), "Idle native navigation was consumed");
      phrase();
      auto expected = seen.committed + seen.candidates.front();
      require(!key(native_key) && seen.committed == expected &&
                  !seen.preedit_visible && !seen.lookup_visible,
              "Disabled navigation lost input or intercepted the editor key");
    }
    phrase();
    auto expected_punctuation = seen.committed + seen.candidates.front() + "。";
    require(key(IBUS_period) && seen.committed == expected_punctuation,
            "Disabled period paging did not restore punctuation");
    options["preferences"]["navigation"]["minus_equal"] = true;
    save(revision++, 4);
    settle();
    require(key('U', IBUS_SHIFT_MASK), "Unicode entry failed");
    require(key('+', IBUS_SHIFT_MASK) && seen.preedit == "U+",
            "Equal-key paging intercepted Unicode plus");
    for (char c : std::string("4e2d"))
      require(key(c), "Unicode digit failed");
    require(seen.preedit == "U+4e2d", "Unicode sequence was not preserved");
    require(seen.auxiliary.find("U+") != std::string::npos,
            "Unicode candidate mode indicator missing");
    invoke("Reset");
    require(seen.auxiliary.empty(), "Reset left a stale mode indicator");
    auto edge_text = [](const std::string &text, bool last) {
      auto length = g_utf8_strlen(text.c_str(), -1);
      require(length >= 1, "Expected a nonempty fixture candidate");
      gchar *part = g_utf8_substring(text.c_str(), last ? length - 1 : 0,
                                     last ? length : 1);
      std::string result(part);
      g_free(part);
      return result;
    };
    for (bool minus : {false, true}) {
      const char *group = minus ? "minus_equal" : "brackets";
      for (const auto &binding : bindings)
        options["preferences"]["navigation"][binding.name] = false;
      options["preferences"]["word_character"] = {{"enabled", true},
                                                  {"keys", group}};
      phrase();
      save(revision++, 4);
      settle();
      require(seen.preedit == "nihao", "Edge binding update canceled input");
      auto first = seen.committed + edge_text(seen.candidates.front(), false);
      require(key(minus ? IBUS_minus : IBUS_bracketleft) &&
                  seen.committed == first && !seen.preedit_visible,
              "First Han binding failed");
      phrase();
      invoke("PageDown");
      auto last =
          seen.committed + edge_text(seen.candidates.at(seen.cursor), true);
      require(key(minus ? IBUS_equal : IBUS_bracketright) &&
                  seen.committed == last && !seen.lookup_visible,
              "Last Han binding did not use the displayed global candidate");
      // An invalid simultaneous paging binding must not replace live settings.
      options["preferences"]["navigation"][group] = true;
      save(revision++, 4);
      settle();
      phrase();
      first = seen.committed + edge_text(seen.candidates.front(), false);
      require(key(minus ? IBUS_minus : IBUS_bracketleft) &&
                  seen.committed == first,
              "Conflicting settings replaced the live edge binding");
      options["preferences"]["navigation"][group] = false;
    }
    // A Unicode Latin candidate contains no Han: finish it, then insert the
    // requested punctuation through the shared runtime rather than dropping it.
    options["preferences"]["word_character"]["keys"] = "brackets";
    save(revision++, 4);
    settle();
    require(key('U', IBUS_SHIFT_MASK), "Non-Han fixture entry failed");
    for (char c : std::string("0041"))
      require(key(c), "Non-Han fixture digit failed");
    auto non_han = seen.committed + "A";
    require(key(IBUS_bracketright) && seen.committed.find(non_han) == 0 &&
                seen.committed.size() > non_han.size() && !seen.preedit_visible,
            "Non-Han edge fallback lost candidate or punctuation");
    options["preferences"]["word_character"]["enabled"] = false;
    save(revision++, 4);
    settle();
    phrase();
    auto disabled = seen.committed + seen.candidates.front();
    require(key(IBUS_bracketright) && seen.committed.find(disabled) == 0 &&
                seen.committed.size() > disabled.size() &&
                !seen.preedit_visible,
            "Disabled edge binding did not restore normal punctuation");
    options["preferences"]["word_character"]["enabled"] = true;
    options.erase("preferences_directory");
    msime_preview_configure(options.dump());
    invoke("Set",
           g_variant_new("(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                         g_variant_new("(uu)", IBUS_INPUT_PURPOSE_FREE_FORM,
                                       IBUS_INPUT_HINT_PRIVATE)));
    phrase();
    auto startup = seen.committed + edge_text(seen.candidates.front(), false);
    require(key(IBUS_bracketleft) && seen.committed == startup,
            "Startup edge binding required a preferences reload");
    require(key('U', IBUS_SHIFT_MASK), "Non-BMP fixture entry failed");
    for (char c : std::string("20000"))
      require(key(c), "Non-BMP fixture digit failed");
    auto supplementary = seen.committed + "𠀀";
    require(key(IBUS_bracketright) && seen.committed == supplementary,
            "Supplementary Han selection split a Unicode character");
    phrase();
    auto shifted = seen.committed + seen.candidates.front();
    require(key(IBUS_braceright, IBUS_SHIFT_MASK) &&
                seen.committed.find(shifted) == 0 &&
                seen.committed.size() > shifted.size(),
            "Shifted symbol triggered word-to-character selection");
    invoke("Disable");
    require(!key('n'), "Disabled engine consumed input");
    g_dbus_connection_signal_unsubscribe(client, subscription);
    ibus_object_destroy(IBUS_OBJECT(engine));
    g_object_unref(engine);
    g_dbus_connection_close_sync(client, nullptr, nullptr);
    g_dbus_connection_close_sync(server, nullptr, nullptr);
    g_object_unref(client);
    g_object_unref(server);
    g_test_dbus_down(bus);
    g_object_unref(bus);
    std::cout << "IBus D-Bus shared-runtime acceptance passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}

#include "ClientEngine.h"
#include "msime_client.h"
#include <filesystem>
#include <iostream>
#include <memory>
#include <nlohmann/json.hpp>
#include <stdexcept>
#include <vector>

namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}
struct Observation {
  std::string committed;
  std::string preedit;
  std::vector<std::string> candidates;
  bool lookup_visible = false;
  bool preedit_visible = false;
};
void signal(GDBusConnection *, const gchar *, const gchar *, const gchar *,
            const gchar *name, GVariant *parameters, gpointer data) {
  auto &seen = *static_cast<Observation *>(data);
  if (std::string(name) == "HideLookupTable") {
    seen.lookup_visible = false;
    return;
  }
  if (std::string(name) != "CommitText" &&
      std::string(name) != "UpdatePreeditText" &&
      std::string(name) != "UpdateLookupTable")
    return;
  GVariant *encoded = g_variant_get_child_value(parameters, 0);
  auto object = ibus_serializable_deserialize(encoded);
  g_variant_unref(encoded);
  if (!object)
    std::abort();
  g_object_ref_sink(object);
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
    auto table = IBUS_LOOKUP_TABLE(object);
    for (guint i = 0; i < ibus_lookup_table_get_number_of_candidates(table);
         ++i)
      seen.candidates.emplace_back(
          ibus_text_get_text(ibus_lookup_table_get_candidate(table, i)));
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
    g_setenv("MSIME_DISABLE_IBUS_PROPERTIES", "1", TRUE);
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
    options["preferences"]["candidate_page_size"] = 2;
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
    phrase();
    require(seen.preedit_visible && seen.preedit == "nihao",
            "Preedit signal missing");
    require(seen.lookup_visible && seen.candidates.size() == 2 &&
                seen.candidates[0] == "你好",
            "Candidate signal mismatch");
    require(!key(IBUS_Shift_L) && !key('n', IBUS_RELEASE_MASK),
            "Modifier/release was consumed");
    require(seen.preedit == "nihao", "Modifier/release canceled composition");
    require(key(IBUS_space), "Space not handled");
    require(seen.committed == "你好" && !seen.preedit_visible &&
                !seen.lookup_visible,
            "Commit/clear signal mismatch");
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
    auto committed = seen.committed;
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
    phrase();
    invoke("FocusOut");
    require(!seen.preedit_visible && !seen.lookup_visible && !key('n'),
            "Focus loss did not clear and stop input");
    invoke("Set", g_variant_new(
                      "(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                      g_variant_new("(uu)", IBUS_INPUT_PURPOSE_PASSWORD, 0)));
    invoke("FocusIn");
    require(!key('n') && !seen.preedit_visible && seen.committed == committed,
            "Password input reached engine");
    invoke("Set",
           g_variant_new("(ssv)", "org.freedesktop.IBus.Engine", "ContentType",
                         g_variant_new("(uu)", IBUS_INPUT_PURPOSE_FREE_FORM,
                                       IBUS_INPUT_HINT_PRIVATE)));
    phrase();
    require(key(IBUS_space) && seen.committed == committed + "你好",
            "Private text focus did not recover");
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

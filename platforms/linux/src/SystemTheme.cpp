#include "SystemTheme.h"
#include "ClientEngine.h"
#include <memory>

namespace {
GDBusConnection *connection = nullptr;
GCancellable *pending = nullptr;
guint subscription = 0;
guint64 generation = 0;
constexpr auto service = "org.freedesktop.portal.Desktop";
constexpr auto path = "/org/freedesktop/portal/desktop";
constexpr auto interface = "org.freedesktop.portal.Settings";

void apply_value(GVariant *value) {
  // Settings.Read historically wraps its result in two variants; signals
  // use one. Accept both without relying on a portal implementation version.
  auto current = g_variant_ref(value);
  while (g_variant_is_of_type(current, G_VARIANT_TYPE_VARIANT)) {
    auto inner = g_variant_get_variant(current);
    g_variant_unref(current);
    current = inner;
  }
  if (g_variant_is_of_type(current, G_VARIANT_TYPE_UINT32))
    msime_preview_set_system_dark(g_variant_get_uint32(current) == 1);
  g_variant_unref(current);
}
void disconnect() {
  ++generation;
  if (pending) g_cancellable_cancel(pending);
  g_clear_object(&pending);
  if (connection && subscription)
    g_dbus_connection_signal_unsubscribe(connection, subscription);
  subscription = 0;
  g_clear_object(&connection);
}
void appeared(GDBusConnection *bus, const gchar *, const gchar *, gpointer) {
  disconnect();
  connection = G_DBUS_CONNECTION(g_object_ref(bus));
  pending = g_cancellable_new();
  subscription = g_dbus_connection_signal_subscribe(
      connection, service, interface, "SettingChanged", path,
      "org.freedesktop.appearance", G_DBUS_SIGNAL_FLAGS_NONE,
      +[](GDBusConnection *, const gchar *, const gchar *, const gchar *,
          const gchar *, GVariant *parameters, gpointer) {
        if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(ssv)"))) return;
        const gchar *space = nullptr, *key = nullptr;
        GVariant *value = nullptr;
        g_variant_get(parameters, "(&s&sv)", &space, &key, &value);
        if (g_str_equal(space, "org.freedesktop.appearance") && g_str_equal(key, "color-scheme")) {
          ++generation; // Do not overwrite a newer signal with an old read.
          apply_value(value);
        }
        g_variant_unref(value);
      }, nullptr, nullptr);
  g_dbus_connection_call(connection, service, path, interface, "Read",
      g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1500, pending,
      +[](GObject *source, GAsyncResult *result, gpointer data) {
        std::unique_ptr<guint64> requested(static_cast<guint64 *>(data));
        GError *error = nullptr;
        auto reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
        if (reply) {
          if (*requested == generation) {
            auto value = g_variant_get_child_value(reply, 0);
            apply_value(value);
            g_variant_unref(value);
          }
          g_variant_unref(reply);
        }
        g_clear_error(&error);
      }, new guint64(generation));
}
}

guint msime_watch_system_theme() {
  return g_bus_watch_name(G_BUS_TYPE_SESSION, service, G_BUS_NAME_WATCHER_FLAGS_AUTO_START,
      appeared, +[](GDBusConnection *, const gchar *, gpointer) {
        disconnect();
        msime_preview_set_system_dark(false);
      }, nullptr, nullptr);
}
void msime_unwatch_system_theme(guint watch) {
  g_bus_unwatch_name(watch);
  disconnect();
}

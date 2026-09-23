// Stands in for ibus-daemon on a plain dbus-daemon so a test can run the real msime-client-ibus up to and past component registration without IBus, a desktop session or dictionaries.
// It owns org.freedesktop.IBus and answers only RegisterComponent; every other IBus call the host makes gets GDBus's standard unknown-method or unknown-property error, which the host already treats as "nothing to restore".
// Prints "ready" once it owns the name and "registered <CLOCK_MONOTONIC microseconds> <sender>" for each registration, so the test can order registration against other events without trusting when it reads the pipe, and knows the host's unique bus name.
// With "probe SENDER" it instead asks that host's IBusFactory to create an engine that does not exist and prints "reply <elapsed microseconds> <D-Bus error name>" or "timeout" after 1 s. The factory answers only from the host's main loop, while GDBus can reject a call to an object nobody exported without it, so only the factory's own error proves the main loop is running.
#include <gio/gio.h>

#include <cstdio>

namespace {
constexpr auto introspection = R"(<node>
  <interface name="org.freedesktop.IBus">
    <method name="RegisterComponent"><arg direction="in" type="v" name="component"/></method>
  </interface>
</node>)";

void handle(GDBusConnection *, const gchar *, const gchar *, const gchar *, const gchar *,
            GVariant *, GDBusMethodInvocation *invocation, gpointer) {
  // The only method the interface declares; GDBus rejects the rest before they get here.
  std::printf("registered %" G_GINT64_FORMAT " %s\n", g_get_monotonic_time(),
              g_dbus_method_invocation_get_sender(invocation));
  std::fflush(stdout);
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

int probe(GDBusConnection *connection, const char *sender) {
  GError *error = nullptr;
  const auto started = g_get_monotonic_time();
  auto reply = g_dbus_connection_call_sync(
      connection, sender, "/org/freedesktop/IBus/Factory", "org.freedesktop.IBus.Factory",
      "CreateEngine", g_variant_new("(s)", "no-such-engine"), G_VARIANT_TYPE("(o)"),
      G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  const auto elapsed = g_get_monotonic_time() - started;
  if (reply) {
    g_variant_unref(reply);
    std::printf("reply %" G_GINT64_FORMAT " success\n", elapsed);
    return 0;
  }
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_TIMED_OUT)) {
    std::printf("timeout\n");
    return 0;
  }
  auto name = g_dbus_error_get_remote_error(error);
  std::printf("reply %" G_GINT64_FORMAT " %s\n", elapsed, name ? name : error->message);
  g_free(name);
  return 0;
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2 && !(argc == 4 && g_strcmp0(argv[2], "probe") == 0)) {
    std::fprintf(stderr, "usage: ibus-registration-bus DBUS_ADDRESS [probe SENDER]\n");
    return 2;
  }
  GError *error = nullptr;
  auto connection = g_dbus_connection_new_for_address_sync(
      argv[1],
      static_cast<GDBusConnectionFlags>(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT |
                                        G_DBUS_CONNECTION_FLAGS_MESSAGE_BUS_CONNECTION),
      nullptr, nullptr, &error);
  if (!connection) {
    std::fprintf(stderr, "cannot connect: %s\n", error->message);
    return 1;
  }
  if (argc == 4)
    return probe(connection, argv[3]);
  auto node = g_dbus_node_info_new_for_xml(introspection, &error);
  if (!node) {
    std::fprintf(stderr, "bad introspection: %s\n", error->message);
    return 1;
  }
  static const GDBusInterfaceVTable vtable{handle, nullptr, nullptr, {}};
  if (!g_dbus_connection_register_object(connection, "/org/freedesktop/IBus", node->interfaces[0],
                                         &vtable, nullptr, nullptr, &error)) {
    std::fprintf(stderr, "cannot export: %s\n", error->message);
    return 1;
  }
  auto reply = g_dbus_connection_call_sync(
      connection, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
      "RequestName", g_variant_new("(su)", "org.freedesktop.IBus", 4u /* DO_NOT_QUEUE */),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
  guint32 result = 0;
  if (reply) {
    g_variant_get(reply, "(u)", &result);
    g_variant_unref(reply);
  }
  if (result != 1 /* PRIMARY_OWNER */) {
    std::fprintf(stderr, "cannot own org.freedesktop.IBus\n");
    return 1;
  }
  std::printf("ready\n");
  std::fflush(stdout);
  auto loop = g_main_loop_new(nullptr, FALSE);
  g_main_loop_run(loop);
  return 0;
}

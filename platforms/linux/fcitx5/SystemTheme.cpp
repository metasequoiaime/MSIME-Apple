#include "SystemTheme.h"

#include <gio/gio.h>

namespace msime::fcitx_host {

std::optional<bool> fcitx_system_dark_theme() {
  GError *error = nullptr;
  auto *connection = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (!connection) {
    g_clear_error(&error);
    return std::nullopt;
  }
  auto *reply = g_dbus_connection_call_sync(
      connection, "org.freedesktop.portal.Desktop",
      "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
      "Read", g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 1000, nullptr, &error);
  g_object_unref(connection);
  if (!reply) {
    g_clear_error(&error);
    return std::nullopt;
  }
  GVariant *value = nullptr;
  g_variant_get(reply, "(v)", &value);
  g_variant_unref(reply);
  while (value && g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    auto *inner = g_variant_get_variant(value);
    g_variant_unref(value);
    value = inner;
  }
  if (!value || !g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    if (value) g_variant_unref(value);
    return std::nullopt;
  }
  const auto scheme = g_variant_get_uint32(value);
  g_variant_unref(value);
  // Portal color-scheme 1 is prefer-dark; 0 and 2 are light/no-preference.
  return scheme == 1;
}

}  // namespace msime::fcitx_host

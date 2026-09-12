#include "ClientEngine.h"
#include "SystemTheme.h"
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>

namespace {
struct OptionsWatch {
  const char *path;
  GFile *file;
  guint debounce = 0;
  std::string last_document;
};
void reload_options(OptionsWatch &watch) {
  std::ifstream file(watch.path);
  if (!file)
    return;
  std::array<char, 16385> buffer;
  file.read(buffer.data(), buffer.size());
  if (file.bad() || file.gcount() == 0 ||
      static_cast<std::size_t>(file.gcount()) >= buffer.size())
    return;
  const std::string document(buffer.data(), static_cast<size_t>(file.gcount()));
  if (document == watch.last_document)
    return;
  // Avoid reparsing identical content, including an invalid intermediate save.
  // A later different document is always eligible for another attempt.
  watch.last_document = document;
  try {
    msime_preview_configure(document);
  } catch (...) {
    g_warning("MSIME preview settings reload failed");
  }
}
} // namespace

int main(int argc, char **argv) {
  if (argc != 2 || argv[1][0] != '/') {
    std::cerr << "usage: msime-client-ibus /absolute/runtime-options.json\n";
    return 2;
  }
  // Panel actions launched from the IBus property menu inherit this process's
  // environment. Keep the direct binary invocation equivalent to the
  // packaged launcher, which already exports the HostOptions path.
  if (!g_setenv("MSIME_CLIENT_HOST_OPTIONS", argv[1], FALSE)) {
    std::cerr << "Cannot export runtime options path\n";
    return 1;
  }
  try {
    std::ifstream file(argv[1]);
    if (!file)
      throw std::runtime_error("Missing configuration");
    std::array<char, 16385> buffer;
    file.read(buffer.data(), buffer.size());
    if (file.bad())
      throw std::runtime_error("Cannot read configuration");
    std::string options(buffer.data(), static_cast<size_t>(file.gcount()));
    msime_preview_configure(options);
  } catch (...) {
    std::cerr << "Cannot load preview configuration\n";
    return 1;
  }
  ibus_init();
  auto bus = ibus_bus_new();
  if (!ibus_bus_is_connected(bus)) {
    g_object_unref(bus);
    return 1;
  }
  auto factory = ibus_factory_new(ibus_bus_get_connection(bus));
  ibus_factory_add_engine(factory, "msime-client-preview",
                          msime_preview_engine_get_type());
  auto component = ibus_component_new(
      "app.msime.client.preview", "MSIME Client preview", "0.1.0",
      "GPL-3.0-only", "MSIME contributors",
      "https://github.com/metasequoiaime/MSIME-Client", "", "");
  ibus_component_add_engine(
      component,
      ibus_engine_desc_new("msime-client-preview", "MSIME Client Preview",
                           "Shared client runtime preview", "zh",
                           "GPL-3.0-only", "MSIME contributors", "", "us"));
  if (!ibus_bus_register_component(bus, component)) {
    g_object_unref(component);
    g_object_unref(factory);
    g_object_unref(bus);
    return 1;
  }
  g_signal_connect(bus, "disconnected",
                   G_CALLBACK(+[](IBusBus *, gpointer) { ibus_quit(); }),
                   nullptr);
  auto config_file = g_file_new_for_path(argv[1]);
  OptionsWatch options_watch{argv[1], config_file, 0, {}};
  auto config_directory = g_file_get_parent(config_file);
  auto monitor = config_directory
      ? g_file_monitor_directory(config_directory, G_FILE_MONITOR_WATCH_MOVES, nullptr, nullptr)
      : nullptr;
  if (config_directory) g_object_unref(config_directory);
  if (monitor) {
    g_signal_connect(
        monitor, "changed",
        G_CALLBACK(+[](GFileMonitor *, GFile *file, GFile *other, GFileMonitorEvent,
                       gpointer data) {
          auto &watch = *static_cast<OptionsWatch *>(data);
          if ((!file || !g_file_equal(file, watch.file)) &&
              (!other || !g_file_equal(other, watch.file)))
            return;
          if (watch.debounce) g_source_remove(watch.debounce);
          watch.debounce = g_timeout_add(100, +[](gpointer data) -> gboolean {
            auto &watch = *static_cast<OptionsWatch *>(data);
            watch.debounce = 0;
            reload_options(watch);
            return G_SOURCE_REMOVE;
          }, data);
        }),
        &options_watch);
  }
  // Also covers unavailable monitors, replaced parent directories and symlink
  // targets changed outside the watched directory.
  const auto options_poll = g_timeout_add_seconds(5, +[](gpointer data) -> gboolean {
    reload_options(*static_cast<OptionsWatch *>(data));
    return G_SOURCE_CONTINUE;
  }, &options_watch);
  const auto theme_watch = msime_watch_system_theme();
  ibus_main();
  msime_unwatch_system_theme(theme_watch);
  g_source_remove(options_poll);
  if (options_watch.debounce) g_source_remove(options_watch.debounce);
  if (monitor) {
    g_file_monitor_cancel(monitor);
    g_object_unref(monitor);
  }
  g_object_unref(config_file);
  g_object_unref(component);
  g_object_unref(factory);
  g_object_unref(bus);
}

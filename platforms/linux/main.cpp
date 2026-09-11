#include "ClientEngine.h"
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>

namespace {
void reload_options(const char *path) {
  std::ifstream file(path);
  if (!file)
    return;
  std::array<char, 16385> buffer;
  file.read(buffer.data(), buffer.size());
  if (file.bad() || file.gcount() == 0 ||
      static_cast<std::size_t>(file.gcount()) >= buffer.size())
    return;
  try {
    msime_preview_configure(
        std::string(buffer.data(), static_cast<size_t>(file.gcount())));
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
  auto monitor = g_file_monitor_file(config_file, G_FILE_MONITOR_NONE, nullptr,
                                     nullptr);
  if (monitor) {
    g_signal_connect(
        monitor, "changed",
        G_CALLBACK(+[](GFileMonitor *, GFile *, GFile *, GFileMonitorEvent event,
                       gpointer data) {
          if (event == G_FILE_MONITOR_EVENT_CHANGED ||
              event == G_FILE_MONITOR_EVENT_CREATED ||
              event == G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT ||
              event == G_FILE_MONITOR_EVENT_MOVED_IN ||
              event == G_FILE_MONITOR_EVENT_MOVED ||
              event == G_FILE_MONITOR_EVENT_RENAMED)
            reload_options(static_cast<const char *>(data));
        }),
        argv[1]);
  }
  ibus_main();
  if (monitor)
    g_object_unref(monitor);
  g_object_unref(config_file);
  g_object_unref(component);
  g_object_unref(factory);
  g_object_unref(bus);
}

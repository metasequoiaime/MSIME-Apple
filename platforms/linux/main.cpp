#include "ClientEngine.h"
#include <array>
#include <fstream>
#include <iostream>
#include <iterator>

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
  ibus_main();
  g_object_unref(component);
  g_object_unref(factory);
  g_object_unref(bus);
}

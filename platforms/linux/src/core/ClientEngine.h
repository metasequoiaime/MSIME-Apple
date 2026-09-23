#pragma once
#include <ibus.h>
#include <string>

GType msime_ibus_engine_get_type();
// Set once before registering the factory. The document is prepared by
// host-api.
void msime_ibus_configure(const std::string &options);
void msime_ibus_set_system_dark(bool dark);
// Exit status of msime-client-ibus after the Ctrl+Shift+Alt+T maintenance stop. msime-client-ibus-launcher supervises the process and restarts it after a crash; this status tells it the stop was deliberate. Keep the value in step with stop_status in that script.
constexpr int msime_ibus_maintenance_stop_exit = 77;
// True once the maintenance stop shortcut has quit the IBus main loop.
bool msime_ibus_maintenance_stop_requested();

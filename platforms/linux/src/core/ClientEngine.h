#pragma once
#include <ibus.h>
#include <string>

GType msime_ibus_engine_get_type();
// Set once before registering the factory. The document is prepared by
// host-api.
void msime_ibus_configure(const std::string &options);
void msime_ibus_set_system_dark(bool dark);
// Exit status of msime-linux-ibus after the Ctrl+Shift+Alt+T maintenance stop. msime-linux-ibus-launcher supervises the process and restarts it after a crash; this status tells it the stop was deliberate. Keep the value in step with stop_status in that script.
constexpr int msime_ibus_maintenance_stop_exit = 77;
// True once the maintenance stop shortcut has quit the IBus main loop.
bool msime_ibus_maintenance_stop_requested();
// Exit status of msime-linux-ibus after it found its own program replaced by an upgrade and quit so the new build can take over. The launcher restarts it at once with --recovered, without the crash backoff; keep the value in step with upgraded_status in that script.
constexpr int msime_ibus_upgraded_exit = 78;
// True once an upgrade restart has quit the IBus main loop.
bool msime_ibus_upgrade_restart_requested();

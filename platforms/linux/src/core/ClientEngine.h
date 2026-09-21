#pragma once
#include <ibus.h>
#include <string>

GType msime_ibus_engine_get_type();
// Set once before registering the factory. The document is prepared by
// host-api.
void msime_ibus_configure(const std::string &options);
void msime_ibus_set_system_dark(bool dark);

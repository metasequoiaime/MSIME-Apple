#pragma once
#include <ibus.h>
#include <string>

GType msime_preview_engine_get_type();
// Set once before registering the factory. The document is prepared by
// host-api.
void msime_preview_configure(const std::string &options);

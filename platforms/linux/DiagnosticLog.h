#pragma once

#include <string>
#include <string_view>

// Linux host diagnostics deliberately accept only state/event labels from the
// host. Callers must never pass key values, input text, candidates, paths, or
// provider responses.
void msime_linux_diagnostic_configure(const std::string &directory,
                                      bool enabled);
void msime_linux_diagnostic_write(std::string_view event);

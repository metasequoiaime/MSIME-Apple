#pragma once

#include <string>
#include <string_view>

// macOS host diagnostics are deliberately limited to state/event labels.
// They never receive keystrokes, input text, candidates, credentials, or
// provider responses.
void msime_macos_diagnostic_configure(const std::string &directory,
                                      bool enabled) noexcept;
void msime_macos_diagnostic_write(std::string_view event) noexcept;

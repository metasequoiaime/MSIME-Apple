#pragma once

#include <string>
#include <string_view>

// macOS host diagnostics are deliberately limited to state/event labels, counts, geometry, timings and error categories. They never receive keystrokes, input text, candidates, credentials, or provider responses.
void msime_macos_diagnostic_configure(const std::string &directory,
                                      bool enabled) noexcept;
void msime_macos_diagnostic_write(std::string_view event) noexcept;

// One relaxed load, so hot paths such as key handling and candidate layout can skip timing and formatting entirely while the log is off, like MSIME-Windows' CandidateDiagLog::IsEnabled().
bool msime_macos_diagnostic_enabled() noexcept;

// printf-style write for call sites that format numbers. Returns at once while the log is off; the formatted event is cut to the same per-event cap as msime_macos_diagnostic_write.
void msime_macos_diagnostic_writef(const char *format, ...) noexcept
    __attribute__((format(printf, 1, 2)));

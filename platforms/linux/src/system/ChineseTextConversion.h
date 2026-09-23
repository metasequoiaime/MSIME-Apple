#pragma once

#include <string>

// Convert simplified Chinese display/commit text with the shared OpenCC s2t tables exported by msime-host-api (phrase-level, identical to Windows). Text without a Traditional form is returned unchanged; text the host API rejects (invalid UTF-8, embedded NUL) is returned as is.
std::string msime_linux_simplified_to_traditional(const std::string &text);

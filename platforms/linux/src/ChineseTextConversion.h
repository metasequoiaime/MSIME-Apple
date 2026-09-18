#pragma once

#include <string>

// Convert simplified Chinese display/commit text using the platform's ICU
// transliteration data. Non-Chinese characters are preserved by ICU.
std::string msime_linux_simplified_to_traditional(const std::string &text);

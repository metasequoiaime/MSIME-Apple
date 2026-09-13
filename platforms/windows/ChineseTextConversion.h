#pragma once

#include <string>
#include <string_view>

namespace msime::windows {

// Convert simplified Chinese output at the Windows host boundary. The Engine
// keeps its canonical text unchanged; malformed or unsupported text is kept.
std::string simplified_to_traditional(std::string_view text,
                                      bool traditional_output);

} // namespace msime::windows

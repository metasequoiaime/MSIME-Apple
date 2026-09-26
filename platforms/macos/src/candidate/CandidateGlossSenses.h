#pragma once

#include "../../../../shared/input/GlossSenses.h"

#include <string>
#include <string_view>
#include <vector>

namespace msime::mac {

// The senses inside one candidate's gloss, which the macOS sub-page offers on Ctrl+Enter. The rule is shared with every other host - see shared/input/GlossSenses.h.
inline std::vector<std::string> candidate_gloss_senses(std::string_view gloss)
{
    return msime::input::gloss_senses(gloss);
}

} // namespace msime::mac

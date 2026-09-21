#pragma once

#include <string>
#include <string_view>
#include <vector>

namespace msime::mac {

// The senses inside one candidate's gloss.
//
// The packaged dictionary joins several senses of a word with a semicolon - ASCII in the English
// entries, full-width in the Chinese ones. Ctrl+Enter offers them as choices rather than committing
// the joined display text, which is what every other host does: Windows splits them in its own
// `CandidateTranslationPolicy.h`, both Linux front ends in theirs, and the rule is the same in all
// three - cut on either separator, trim the surrounding whitespace, and drop what is left empty.
//
// `platforms/macos/tests/candidate/TranslationSensesAgreementTest.cpp` compiles all three headers
// together and checks they answer alike, because three copies of a rule drift silently.
inline std::vector<std::string> candidate_gloss_senses(std::string_view gloss)
{
    static constexpr std::string_view fullwidth = "\xEF\xBC\x9B";
    std::vector<std::string> senses;
    const auto append = [&senses](std::string_view value) {
        const auto first = value.find_first_not_of(" \t\r\n");
        if (first == std::string_view::npos) return;
        const auto last = value.find_last_not_of(" \t\r\n");
        senses.emplace_back(value.substr(first, last - first + 1));
    };
    std::size_t start = 0;
    while (start <= gloss.size())
    {
        const auto ascii = gloss.find(';', start);
        const auto wide = gloss.find(fullwidth, start);
        const auto cut = ascii < wide ? ascii : wide;
        if (cut == std::string_view::npos)
        {
            append(gloss.substr(start));
            break;
        }
        append(gloss.substr(start, cut - start));
        start = cut + (cut == wide ? fullwidth.size() : 1);
    }
    return senses;
}

} // namespace msime::mac

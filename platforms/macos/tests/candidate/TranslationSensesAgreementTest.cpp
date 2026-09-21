#include "../../src/candidate/CandidateGlossSenses.h"
#include "../../../windows/src/candidate/CandidateTranslationPolicy.h"
#include "../../../linux/src/candidates/CandidateTranslationPolicy.h"

#include <cassert>
#include <string>
#include <vector>

// The same rule, written three times, asked the same questions.
//
// Splitting a candidate's gloss into its senses is host-independent - the dictionary decides what a
// separator is - but each host carries its own copy: Windows because its policy header predates the
// others, Linux because its two front ends share one, and macOS because it draws its own sub-page.
// Three copies of a rule drift, and the drift is invisible: a sense that stops being offered on one
// platform looks like a dictionary difference.
//
// This host is the one that can compile all three - every one of them is plain C++ with no platform
// header - so the comparison lives here.
int main()
{
    const std::vector<std::string> fixtures = {
        // The ordinary shapes: one sense, several ASCII-separated, several full-width separated.
        "hello",
        "hello; hi; greetings",
        "你好；嗨",
        "mixed; 混合；both",
        // Whitespace around separators, and a trailing one.
        "  padded  ;  sides  ",
        "trailing;",
        ";leading",
        // Nothing but separators and spaces: no sense survives.
        ";;;",
        "  ",
        "",
        "；；",
        // Repeated separators leave no empty sense between them.
        "a;;b",
        "a；；b",
        // A byte that shares the full-width separator's lead byte but is a different character, so
        // a split that matched on one byte would cut it in half.
        "， comma",
        // Newlines are the host's column separator, not a sense separator: they must survive.
        "first line\nsecond line",
        "line one; two\nline two",
    };

    for (const auto &fixture : fixtures)
    {
        const auto mac = msime::mac::candidate_gloss_senses(fixture);
        const auto windows = msime::windows::translation_senses(fixture);
        const auto linux_host = msime::linux_host::split_translation_gloss(fixture);
        assert(mac == windows);
        assert(mac == linux_host);
    }

    // And the answers themselves, so all three agreeing on something wrong still fails.
    assert(msime::mac::candidate_gloss_senses("hello; hi").size() == 2);
    assert(msime::mac::candidate_gloss_senses("hello; hi")[1] == "hi");
    assert(msime::mac::candidate_gloss_senses(";;;").empty());
    assert(msime::mac::candidate_gloss_senses("first\nsecond").size() == 1);
    assert(msime::windows::first_translation_sense("hello; hi") == "hello");
    return 0;
}

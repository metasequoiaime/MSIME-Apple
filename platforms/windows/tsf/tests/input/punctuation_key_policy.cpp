#include "../../Global/CandidatePunctuationKeyPolicy.h"
#include "../../Global/PairedPunctuationHostPolicy.h"
#include <cstdio>
#include <cstdlib>
#include <string_view>

namespace {
int failures = 0;

void check(bool condition, const char *what) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", what);
        ++failures;
    }
}
} // namespace

int main() {
    using namespace Global;

    // Step-over: only a single closing half of an auto-completed pair qualifies.
    check(PairedPunctuationStepOverCandidate(L')', L"）") == L'）', "full-width paren closes");
    check(PairedPunctuationStepOverCandidate(L']', L"】") == L'】', "lenticular bracket closes");
    check(PairedPunctuationStepOverCandidate(L'>', L"》") == L'》', "book title mark closes");
    check(PairedPunctuationStepOverCandidate(L'}', L"}") == L'}', "brace closes");
    check(PairedPunctuationStepOverCandidate(L'"', L"“") == L'”', "double quote is keyed, not resolved");
    check(PairedPunctuationStepOverCandidate(L'"', L"”") == L'”', "double quote right half");
    check(PairedPunctuationStepOverCandidate(L'\'', L"‘") == L'’', "single quote is keyed, not resolved");
    check(PairedPunctuationStepOverCandidate(L'.', L"。") == 0, "full stop never steps over");
    check(PairedPunctuationStepOverCandidate(L':', L"：") == 0, "colon never steps over");
    check(PairedPunctuationStepOverCandidate(L'.', L".") == 0, "ascii dot never steps over");
    check(PairedPunctuationStepOverCandidate(L'(', L"（") == 0, "opening half never steps over");
    check(PairedPunctuationStepOverCandidate(L'^', L"……") == 0, "multi-character output never steps over");
    check(PairedPunctuationStepOverCandidate(L')', L"") == 0, "empty output never steps over");

    // Candidate navigation keeps paging on the main-row -/= and Tab, but not on the numpad arithmetic keys.
    check(IsCandidateNavigationKeyBeforePunctuation(0xBD), "main-row minus pages");
    check(IsCandidateNavigationKeyBeforePunctuation(0xBB), "main-row equals pages");
    check(IsCandidateNavigationKeyBeforePunctuation(0x09), "tab navigates");
    check(IsCandidateNavigationKeyBeforePunctuation(0x21) && IsCandidateNavigationKeyBeforePunctuation(0x22), "page up/down navigate");
    check(IsCandidateNavigationKeyBeforePunctuation(0x24) && IsCandidateNavigationKeyBeforePunctuation(0x23), "home/end navigate");
    check(!IsCandidateNavigationKeyBeforePunctuation(0x6D), "numpad minus commits the candidate");
    check(!IsCandidateNavigationKeyBeforePunctuation(0x6B), "numpad plus commits the candidate");
    check(!IsCandidateNavigationKeyBeforePunctuation(0x6E), "numpad decimal commits the candidate");
    check(!IsCandidateNavigationKeyBeforePunctuation(0x6F), "numpad divide commits the candidate");
    check(!IsCandidateNavigationKeyBeforePunctuation(0xBF), "slash commits the candidate");

    // The character appended after the committed candidate stays literal for the numpad keys and '/'.
    check(LiteralCandidatePunctuation(0x6B, L'+') == L'+', "numpad plus is literal");
    check(LiteralCandidatePunctuation(0x6D, L'-') == L'-', "numpad minus is literal");
    check(LiteralCandidatePunctuation(0x6E, L'.') == L'.', "numpad decimal is literal");
    check(LiteralCandidatePunctuation(0x6E, L',') == L'.', "numpad decimal is '.' whatever the layout reports");
    check(LiteralCandidatePunctuation(0x6F, L'/') == L'/', "numpad divide is literal");
    check(LiteralCandidatePunctuation(0xBF, L'/') == L'/', "main-row slash is literal");
    check(LiteralCandidatePunctuation(0xBC, L',') == 0, "comma is translated");
    check(LiteralCandidatePunctuation(0xBE, L'.') == 0, "main-row period is translated");
    check(LiteralCandidatePunctuation(0xBD, L'-') == 0, "main-row minus is not literal");

    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

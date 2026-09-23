// The paired-punctuation completion lives in KeyHandler.cpp, which needs the whole TSF to build, so this checks the wiring in its source: the auto-close must go through the pair stack and the focus-token-guarded caret move, never a bare PostMessage the handler would drop. Run from the repository root, or pass the TSF source directory.
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>

namespace {
int failures = 0;

std::string read(const std::string &path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        std::fprintf(stderr, "FAIL: cannot open %s\n", path.c_str());
        std::exit(EXIT_FAILURE);
    }
    std::ostringstream text;
    text << file.rdbuf();
    return text.str();
}

void expect(const std::string &text, const char *needle, bool present, const char *what) {
    if ((text.find(needle) != std::string::npos) != present) {
        std::fprintf(stderr, "FAIL: %s\n", what);
        ++failures;
    }
}
} // namespace

int main(int argc, char **argv) {
    const std::string root = argc > 1 ? argv[1] : "platforms/windows/tsf";
    const std::string handler = read(root + "/Key/KeyHandler.cpp");
    expect(handler, "_TryStepOverPairedPunctuation(ec, pContext,", true, "a typed closing half steps over the auto-completed one");
    expect(handler, "BalanceNestPairAfterAutoClose(", true, "the auto-close balances the nest-pair count");
    expect(handler, "SendPairedPunctuationAutoClosedToServerViaNamedPipe(wch)", true, "the auto-close also balances the count in the Server's Engine");
    expect(handler, "_PushPairedPunctuation(", true, "the auto-close records the pair");
    expect(handler, "_QueuePairedPunctuationCaretMove(-1)", true, "the caret move carries the focus token");
    expect(handler, "PostMessage(_msgWndHandle, WM_PairedPunctuationCaretMove", false, "no untokened caret move that the handler drops");

    const std::string globals = read(root + "/Global/Globals.cpp");
    const auto table = globals.find("CommitWithHighlightedCandPunc");
    const auto end = table == std::string::npos ? table : globals.find("};", table);
    if (table == std::string::npos || end == std::string::npos) {
        std::fprintf(stderr, "FAIL: CommitWithHighlightedCandPunc not found\n");
        ++failures;
    } else {
        expect(globals.substr(table, end - table), "L'/'", true, "'/' commits the highlighted candidate");
    }
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}

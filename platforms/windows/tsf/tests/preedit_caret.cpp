#include "../Composition/PreeditCaret.h"
#include <cstdlib>
#include <limits>
using msime::tsf::MapPreeditCaret;
int main() {
    if (MapPreeditCaret(L"nihao", 3, L"ni'hao", 0) != 4 ||
        MapPreeditCaret(L"ni'hao", 3, L"ni'hao", 0) != 3 ||
        MapPreeditCaret(L"ni'hao", 2, L"ni'hao", 0) != 2 ||
        MapPreeditCaret(L"ni'hao", 4, L"ni'hao", 0) != 4 ||
        MapPreeditCaret(L"hao", 1, L"你hao", 1) != 2 ||
        MapPreeditCaret(L"hao", 0, L"你hao", 1) != 1 ||
        MapPreeditCaret(L"hao", 2, L"", 0) != 0 ||
        MapPreeditCaret(L"", 9, L"", 0) != 0 ||
        MapPreeditCaret(L"a", 99, L"a", 99) != 1 ||
        MapPreeditCaret(L"abc", (std::numeric_limits<std::size_t>::max)(), L"ab", 0) != 2)
        return EXIT_FAILURE;
    // Explicit surrogate code units exercise Windows offsets even when this
    // test runs on a host whose wchar_t is 32 bits.
    const std::wstring_view prefixed = L"\xD83C\xDF32hao";
    if (MapPreeditCaret(L"hao", 1, prefixed, 2) != 3) return EXIT_FAILURE;
    // A host caret must not be replaced by the stale legacy buffer's caret.
    if (MapPreeditCaret(L"nihao", 1, L"ni'hao", 0) != 1 ||
        MapPreeditCaret(L"nihao", 4, L"ni'hao", 0) != 5) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}

#include "../../src/core/WubiCodeHintPolicy.h"

#include <cassert>
#include <string>

int main() {
    using msime::mac::WubiCodeHint;
    assert(WubiCodeHint("wq", "w", true, 2, "none", false) == "q");
    assert(WubiCodeHint("wq", "wq", true, 2, "none", false).empty());
    assert(WubiCodeHint("wq", "x", true, 2, "none", false).empty());
    assert(WubiCodeHint("wq", "w", false, 2, "none", false).empty());
    assert(WubiCodeHint("wq", "w", true, 1, "none", false).empty());
    assert(WubiCodeHint("wq", "w", true, 2, "unicode", false).empty());
    assert(WubiCodeHint("wq", "w", true, 2, "none", true).empty());
    std::string oversized(65, 'a');
    assert(WubiCodeHint(oversized, "a", true, 2, "none", false).empty());
    return 0;
}

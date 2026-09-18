#include "../ModulePath.h"
#include <algorithm>
#include <cstdlib>

int main() {
    for (const unsigned length : {0u, 20u, 259u, 260u, 1024u, 32767u, 32768u}) {
        const std::wstring expected(length, L'x');
        unsigned calls = 0;
        const auto path = msime::tsf::ReadModulePath([&](wchar_t *buffer, unsigned size) {
            ++calls;
            const unsigned copied = (std::min)(size, length);
            std::copy_n(expected.data(), copied, buffer);
            return copied;
        });
        if (length < 32768 && path != expected) return EXIT_FAILURE;
        if (length == 32768 && !path.empty()) return EXIT_FAILURE;
        if ((length < 260 && calls != 1) || (length >= 260 && calls < 2)) return EXIT_FAILURE;
    }
    unsigned calls = 0;
    const auto failed = msime::tsf::ReadModulePath([&](wchar_t *, unsigned size) {
        return ++calls == 1 ? size : 0u;
    });
    if (!failed.empty() || calls != 2) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}

#pragma once
#include <string>
#include <vector>

namespace msime::tsf {
// GetModuleFileNameW reports the buffer size when truncated. Never use a
// truncated filename to derive a resource root, even on legacy Windows.
template<class Reader>
std::wstring ReadModulePath(Reader read) {
    for (unsigned capacity = 260; capacity <= 32768;) {
        std::vector<wchar_t> buffer(capacity);
        const auto length = read(buffer.data(), capacity);
        if (length == 0) return {};
        if (length < capacity) return std::wstring(buffer.data(), length);
        if (capacity == 32768) return {};
        capacity = capacity > 16384 ? 32768 : capacity * 2;
    }
    return {};
}
}

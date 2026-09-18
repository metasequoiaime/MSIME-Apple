#pragma once

#include <string>
#include <string_view>

namespace msime::mac {

constexpr int kWubiScheme = 2;
constexpr std::size_t kWubiCodeHintMaxLength = 64;

/// Return only the code suffix that remains after the currently typed Wubi prefix.
/// Fallback and local-mode candidates deliberately do not advertise Wubi keys.
inline std::string WubiCodeHint(std::string_view code, std::string_view typed, bool enabled, int scheme,
                                std::string_view localMode, bool answeredByPinyinFallback) {
    if (!enabled || scheme != kWubiScheme || answeredByPinyinFallback || localMode != "none" || typed.empty() ||
        code.size() > kWubiCodeHintMaxLength || typed.size() > kWubiCodeHintMaxLength || code.size() <= typed.size() ||
        code.compare(0, typed.size(), typed) != 0) {
        return {};
    }
    return std::string(code.substr(typed.size()));
}

} // namespace msime::mac

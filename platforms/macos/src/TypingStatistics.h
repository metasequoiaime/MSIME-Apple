#pragma once

#include <string_view>

namespace msime::mac {

enum class TypingSource {
    Quanpin,
    NineKey,
    Shuangpin,
    Ziranma,
    Microsoft,
    Shoudao,
    Wubi,
    Japanese,
    Handwriting,
    English,
    Local,
    Ai,
    Reply,
    Voice,
    Unknown,
};

constexpr std::string_view TypingSourceId(TypingSource source) {
    switch (source) {
    case TypingSource::Quanpin: return "quanpin";
    case TypingSource::NineKey: return "nineKey";
    case TypingSource::Shuangpin: return "shuangpin";
    case TypingSource::Ziranma: return "ziranma";
    case TypingSource::Microsoft: return "microsoft";
    case TypingSource::Shoudao: return "shoudao";
    case TypingSource::Wubi: return "wubi";
    case TypingSource::Japanese: return "japanese";
    case TypingSource::Handwriting: return "handwriting";
    case TypingSource::English: return "english";
    case TypingSource::Local: return "local";
    case TypingSource::Ai: return "ai";
    case TypingSource::Reply: return "reply";
    case TypingSource::Voice: return "voice";
    case TypingSource::Unknown: return "unknown";
    }
    return "unknown";
}

// View exposes the applied Engine scheme: 0 quanpin, 1 shuangpin, 2 wubi,
// 3 Japanese. Local modes take precedence, matching the other native hosts.
constexpr TypingSource ResolveTypingSource(int scheme, bool nineKey,
                                            bool dedicatedEnglish,
                                            std::string_view localMode,
                                            std::string_view shuangpinProfile) {
    if (localMode == "temporary_japanese") return TypingSource::Japanese;
    if (!localMode.empty() && localMode != "none") return TypingSource::Local;
    if (dedicatedEnglish) return TypingSource::English;
    switch (scheme) {
    case 0: return nineKey ? TypingSource::NineKey : TypingSource::Quanpin;
    case 1:
        if (shuangpinProfile == "ziranma") return TypingSource::Ziranma;
        if (shuangpinProfile == "microsoft") return TypingSource::Microsoft;
        if (shuangpinProfile == "shoudao") return TypingSource::Shoudao;
        return TypingSource::Shuangpin;
    case 2: return TypingSource::Wubi;
    case 3: return TypingSource::Japanese;
    default: return TypingSource::Unknown;
    }
}

} // namespace msime::mac

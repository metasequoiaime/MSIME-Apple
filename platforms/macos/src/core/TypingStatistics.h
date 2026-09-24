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

// A key the input method hands back to the application is typed by the application itself, so it never reaches a commit path; this decides whether such a key counts, mirroring `ShouldCountPassthroughChar` in MSIME-Windows windows/src/Statistics/stats_passthrough.h. Like the source it is a key-time prediction, not an edit confirmation: a key the application treats as a shortcut or drops in a read-only field is still counted.
//
// Command and Control are the shortcut modifiers, the role Ctrl, Alt and Win play in the source. Option is allowed on purpose: on macOS it is the character layer, like AltGr on Windows, and produces characters such as the euro sign, the em dash and, on German or French layouts, @ [ { |. Control characters, DEL and lone surrogates are rejected as in the source, and so is the AppKit function-key range 0xF700-0xF8FF, which is where arrows, F-keys, Home/End and forward delete land in `NSEvent.characters`.
constexpr bool ShouldCountPassthroughCharacter(char16_t ch, bool control, bool command) {
    if (control || command) return false;
    if (ch < 0x20 || ch == 0x7F) return false;
    if (ch >= 0xD800 && ch <= 0xDFFF) return false;
    if (ch >= 0xF700 && ch <= 0xF8FF) return false;
    return true;
}

} // namespace msime::mac

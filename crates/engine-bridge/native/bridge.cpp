#include "bridge.h"
#include "msime-engine-bridge/src/lib.rs.h"
#include <stdexcept>
#include <metasequoia/personal_dictionary.h>

namespace msime {
namespace {
metasequoia::RuntimePaths paths_for(const EngineOptions& value) {
    return {std::filesystem::u8path(std::string(value.resources)),
            std::filesystem::u8path(std::string(value.user_data)),
            std::filesystem::u8path(std::string(value.cache)),
            std::filesystem::u8path(std::string(value.dictionaries))};
}
metasequoia::PersonalDictionaryEntry entry_for(const DictionaryEntry& value) {
    using Kind = metasequoia::PersonalDictionaryKind;
    Kind kind;
    switch (value.kind) {
        case DictionaryKind::Pinyin: kind = Kind::Pinyin; break;
        case DictionaryKind::Wubi: kind = Kind::Wubi; break;
        case DictionaryKind::QuickPhrase: kind = Kind::QuickPhrase; break;
        case DictionaryKind::English: kind = Kind::English; break;
        default: throw std::invalid_argument("Unsupported dictionary kind");
    }
    return {kind, std::string(value.key), std::string(value.value), value.weight};
}
DictionaryEntry entry_for(const metasequoia::PersonalDictionaryEntry& value) {
    using Kind = metasequoia::PersonalDictionaryKind;
    DictionaryKind kind;
    switch (value.kind) {
        case Kind::Pinyin: kind = DictionaryKind::Pinyin; break;
        case Kind::Wubi: kind = DictionaryKind::Wubi; break;
        case Kind::QuickPhrase: kind = DictionaryKind::QuickPhrase; break;
        case Kind::English: kind = DictionaryKind::English; break;
        default: throw std::invalid_argument("Unsupported dictionary kind");
    }
    return {kind, value.key, value.value, value.weight};
}
metasequoia::SessionOptions options_for(const EngineOptions& value) {
    metasequoia::SessionOptions options;
    options.paths = paths_for(value);
    switch (value.scheme) {
        case 0: options.scheme = SchemeType::Quanpin; break;
        case 1: options.scheme = SchemeType::Shuangpin; break;
        case 2: options.scheme = SchemeType::Wubi; break;
        case 3: options.scheme = SchemeType::JapaneseRomaji; break;
        default: throw std::invalid_argument("Unsupported input scheme");
    }
    switch (value.shuangpin_profile) {
        case 0: options.shuangpin_profile = GetXiaoheShuangpinProfile(); break;
        case 1: options.shuangpin_profile = GetZiranmaShuangpinProfile(); break;
        case 2: options.shuangpin_profile = GetShoudaoShuangpinProfile(); break;
        case 3: options.shuangpin_profile = GetMicrosoftShuangpinProfile(); break;
        default: throw std::invalid_argument("Unsupported shuangpin profile");
    }
    options.learning = value.learning;
    options.autocorrect = value.autocorrect;
    options.chinese_punctuation = value.chinese_punctuation;
    options.helpcode = value.helpcode;
    options.helpcode_schema = std::string(value.helpcode_schema);
    const std::string frequency(value.frequency_mode);
    using metasequoia::FrequencyAdjustmentMode;
    if (frequency == "disabled") options.frequency.mode = FrequencyAdjustmentMode::Disabled;
    else if (frequency == "pin") options.frequency.mode = FrequencyAdjustmentMode::Pin;
    else if (frequency == "halve") options.frequency.mode = FrequencyAdjustmentMode::Halve;
    else if (frequency == "linear") options.frequency.mode = FrequencyAdjustmentMode::Linear;
    else if (frequency == "promote") options.frequency.mode = FrequencyAdjustmentMode::Promote;
    else throw std::invalid_argument("Unsupported frequency mode");
    options.frequency.trigger_count = value.frequency_trigger_count;
    options.frequency.linear_step = value.frequency_linear_step;
    options.english = {value.mixed_english, value.english_minimum_prefix};
    options.expressive = {value.mixed_emoji, value.mixed_kaomoji};
    options.local_modes = {value.local_unicode, value.local_date_time, value.local_quick_phrase, value.local_emoji, value.local_kaomoji, value.local_super_jianpin, value.local_temporary_english, value.local_temporary_japanese};
    return options;
}
EngineResult result_for(const metasequoia::KeyResult& value) {
    return {value.handled, value.commit.has_value(), value.commit.value_or(""), value.diagnostic.value_or("")};
}
const char* local_mode_name(metasequoia::LocalInputMode mode) {
    using metasequoia::LocalInputMode;
    switch (mode) {
        case LocalInputMode::None: return "none";
        case LocalInputMode::Unicode: return "unicode";
        case LocalInputMode::DateTime: return "date_time";
        case LocalInputMode::QuickPhrase: return "quick_phrase";
        case LocalInputMode::Emoji: return "emoji";
        case LocalInputMode::Kaomoji: return "kaomoji";
        case LocalInputMode::SuperJianpin: return "super_jianpin";
        case LocalInputMode::TemporaryEnglish: return "temporary_english";
        case LocalInputMode::TemporaryJapanese: return "temporary_japanese";
    }
    throw std::logic_error("Unknown Engine local mode");
}
}
EngineSession::EngineSession(const EngineOptions& options) : session_(options_for(options)),
    microsoft_shuangpin_(options.scheme == 1 && options.shuangpin_profile == 3),
    shuangpin_profile_(options_for(options).shuangpin_profile.name),
    helpcode_keymap_(options.helpcode ? HelpcodeUtils::load_helpcode_keymap(paths_for(options).resources, std::string(options.helpcode_schema)) : nullptr) {}
std::unique_ptr<EngineSession> create_session(const EngineOptions& options) {
    return std::make_unique<EngineSession>(options);
}
DictionaryPage dictionary_entries(const EngineOptions& options, std::size_t offset, std::size_t limit) {
    auto page = metasequoia::personal_dictionary_entries(paths_for(options), offset, limit);
    if (!page.error.empty()) throw std::runtime_error(page.error);
    DictionaryPage result;
    result.has_more = page.has_more;
    for (const auto& entry : page.entries) result.entries.push_back(entry_for(entry));
    return result;
}
void dictionary_edit(const EngineOptions& options, rust::Slice<const DictionaryEntry> previous,
                     rust::Slice<const DictionaryEntry> replacement, rust::Str request_id) {
    if (previous.size() > 1 || replacement.size() > 1)
        throw std::invalid_argument("Expected at most one dictionary entry");
    std::optional<metasequoia::PersonalDictionaryEntry> before, after;
    if (!previous.empty()) before = entry_for(previous[0]);
    if (!replacement.empty()) after = entry_for(replacement[0]);
    auto result = metasequoia::edit_personal_dictionary(paths_for(options), before, after, std::string(request_id));
    if (!result.success) throw std::runtime_error(result.error);
}
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id) {
    auto paths = metasequoia::prepare_runtime_paths(std::filesystem::u8path(std::string(resources)),
        std::filesystem::u8path(std::string(user_data)), std::filesystem::u8path(std::string(cache)), std::string(content_id));
    return {paths.resources.u8string(), paths.user_data.u8string(), paths.cache.u8string(), paths.dictionaries.u8string(), 0, 0, false, true, true, "ziranma", true, "promote", 1, 1, true, 2, false, false, true, true, true, true, true, true, true, true};
}
EngineSnapshot EngineSession::snapshot() const {
    auto value = session_.snapshot();
    EngineSnapshot output;
    switch (value.scheme) {
        case SchemeType::Quanpin: output.scheme = 0; break;
        case SchemeType::Shuangpin: output.scheme = 1; break;
        case SchemeType::Wubi: output.scheme = 2; break;
        case SchemeType::JapaneseRomaji: output.scheme = 3; break;
        default: output.scheme = 255; break;
    }
    output.local_mode = local_mode_name(value.local_mode);
    output.microsoft_shuangpin = microsoft_shuangpin_;
    output.shuangpin_profile = shuangpin_profile_;
    output.preedit = value.preedit;
    output.editing_text = value.editing_text;
    output.caret_position = value.caret_position;
    // Apple CandidateDisplay.h at b637828: only ordinary pinyin and super jianpin words.
    const bool annotate = helpcode_keymap_ &&
        (value.scheme == SchemeType::Quanpin || value.scheme == SchemeType::Shuangpin) &&
        (value.local_mode == metasequoia::LocalInputMode::None || value.local_mode == metasequoia::LocalInputMode::SuperJianpin);
    for (const auto& candidate : value.candidates) {
        output.candidates.push_back(rust::String(candidate.word));
        output.candidate_annotations.push_back(rust::String(annotate ? HelpcodeUtils::compute_helpcodes(candidate.word, false, helpcode_keymap_.get()) : ""));
    }
    return output;
}
EngineResult EngineSession::character(std::uint8_t value, bool shift) {
    if (value > 127) throw std::invalid_argument("Engine character must be ASCII");
    return result_for(session_.character(static_cast<char>(value), shift));
}
EngineResult EngineSession::command(std::uint8_t value) {
    using metasequoia::Command;
    switch (value) {
        case 0: return result_for(session_.command(Command::Backspace));
        case 1: return result_for(session_.command(Command::CommitCandidate));
        case 2: return result_for(session_.command(Command::CommitRaw));
        case 3: return result_for(session_.command(Command::Cancel));
        case 4: return result_for(session_.command(Command::MoveLeft));
        case 5: return result_for(session_.command(Command::MoveRight));
        case 6: return result_for(session_.command(Command::MoveHome));
        case 7: return result_for(session_.command(Command::MoveEnd));
        case 8: return result_for(session_.command(Command::DeleteForward));
        default: throw std::invalid_argument("Unsupported input command");
    }
}
EngineResult EngineSession::select(std::size_t index) { return result_for(session_.select(index)); }
EngineResult EngineSession::select_edge(std::size_t index, std::uint8_t edge) {
    if (edge > 1) throw std::invalid_argument("Invalid candidate edge");
    return result_for(session_.select_edge(index, edge == 0 ? metasequoia::CandidateEdge::FirstHan
                                                          : metasequoia::CandidateEdge::LastHan));
}
EngineResult EngineSession::finish(std::size_t index) { return result_for(session_.finish(index)); }
EngineResult EngineSession::punctuation(std::uint8_t value) {
    if (value > 127) throw std::invalid_argument("Engine punctuation must be ASCII");
    return result_for(session_.punctuation(static_cast<char>(value)));
}
void EngineSession::set_chinese_punctuation_enabled(bool enabled) {
    session_.set_chinese_punctuation_enabled(enabled);
}
}

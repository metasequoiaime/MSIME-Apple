#include "bridge.h"
#include <metasequoia/personal_dictionary.h>
#include <metasequoia/dictionary_state.h>
#include "msime-engine-bridge/src/lib.rs.h"
#include <stdexcept>

namespace msime {
namespace {
metasequoia::SessionOptions options_for(const EngineOptions& value) {
    metasequoia::SessionOptions options;
    options.paths = {std::filesystem::u8path(std::string(value.resources)),
                     std::filesystem::u8path(std::string(value.user_data)),
                     std::filesystem::u8path(std::string(value.cache)),
                     std::filesystem::u8path(std::string(value.dictionaries))};
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
    options.autocorrect_types = value.autocorrect ? (1u << 0) | (1u << 1) : 0u;
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
    microsoft_shuangpin_(options.scheme == 1 && options.shuangpin_profile == 3) {}
std::unique_ptr<EngineSession> create_session(const EngineOptions& options) {
    return std::make_unique<EngineSession>(options);
}
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id) {
    auto paths = metasequoia::prepare_runtime_paths(std::filesystem::u8path(std::string(resources)),
        std::filesystem::u8path(std::string(user_data)), std::filesystem::u8path(std::string(cache)), std::string(content_id));
    return {paths.resources.u8string(), paths.user_data.u8string(), paths.cache.u8string(), paths.dictionaries.u8string(), 0, 0, false, true, true, "ziranma", true, "promote", 1, 1, true, 2, false, false, true, true, true, true, true, true, true, true};
}
EngineOptions stage_dictionary_state(rust::Str resources, rust::Str generation, rust::Str content_id,
                                     const rust::Vec<DictionaryStateRecord>& records) {
    std::size_t index = 0;
    auto next = [&](metasequoia::DictionaryStateRecord& out) {
        if (index == records.size()) return false;
        const auto& r = records[index++];
        if (r.kind == 0) out = metasequoia::DictionaryStateEntry{static_cast<metasequoia::PersonalDictionaryKind>(r.kind), std::string(r.key), std::string(r.value), r.weight, std::string(r.display), r.deleted, r.user_inserted};
        else if (r.kind == 1) out = metasequoia::DictionaryStatePosition{std::string(r.context), std::string(r.key), std::string(r.value), r.position};
        else out = metasequoia::DictionaryStateSelection{std::string(r.context), std::string(r.key), std::string(r.value), r.count};
        return true;
    };
    auto paths = metasequoia::stage_dictionary_state(std::filesystem::u8path(std::string(resources)), std::filesystem::u8path(std::string(generation)), std::string(content_id), next);
    return {paths.resources.u8string(), paths.user_data.u8string(), paths.cache.u8string(), paths.dictionaries.u8string(), 0, 0, false, true, true, "ziranma", true, "promote", 1, 1, true, 2, false, false, true, true, true, true, true, true};
}
rust::String validate_personal_dictionary(std::uint8_t kind, rust::Str key, rust::Str value) {
    metasequoia::PersonalDictionaryEntry entry;
    entry.kind = static_cast<metasequoia::PersonalDictionaryKind>(kind);
    entry.key = std::string(key);
    entry.value = std::string(value);
    auto result = metasequoia::validate_personal_dictionary_entry(std::move(entry));
    return result.error;
}
EngineSnapshot EngineSession::snapshot() const {
    auto value = session_.snapshot();
    EngineSnapshot output;
    output.local_mode = local_mode_name(value.local_mode);
    output.microsoft_shuangpin = microsoft_shuangpin_;
    output.shuangpin_profile = rust::String(value.shuangpin_profile);
    output.preedit = value.preedit;
    output.editing_text = value.editing_text;
    output.caret_position = value.caret_position;
    for (const auto& candidate : value.candidates) output.candidates.push_back(rust::String(candidate.word));
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
EngineResult EngineSession::pin_candidate(std::size_t index) { return result_for(session_.pin(index)); }
EngineResult EngineSession::remove_candidate(std::size_t index) { return result_for(session_.remove(index)); }
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

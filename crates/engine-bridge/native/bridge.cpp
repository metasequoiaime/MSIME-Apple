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
    output.scheme = static_cast<std::uint8_t>(value.scheme);
    output.shuangpin_profile = rust::String(value.shuangpin_profile);
    output.answered_by_pinyin_fallback = value.answered_by_pinyin_fallback;
    output.preedit = value.preedit;
    output.editing_text = value.editing_text;
    output.caret_position = value.caret_position;
    for (const auto& candidate : value.candidates) {
        output.candidates.push_back(rust::String(candidate.word));
        output.candidate_annotations.push_back(rust::String(candidate.corrected_from));
    }
    return output;
}
OnlineQuerySnapshot EngineSession::online_query() const {
    OnlineQuerySnapshot output;
    const auto query = session_.online_query();
    if (!query.has_value()) return output;
    output.available = true;
    output.scheme = static_cast<std::uint8_t>(query->scheme);
    output.generation = query->generation;
    output.identity = query->identity;
    output.query_text = query->query_text;
    output.cache_key = query->cache_key;
    for (const auto& segment : query->pinyin_segments)
        output.pinyin_segments.push_back(rust::String(segment));
    output.cloud_eligible = query->cloud_eligible;
    output.ai_eligible = query->ai_eligible;
    output.session_id = query->session_id;
    return output;
}
bool EngineSession::apply_online_candidate(const OnlineQuerySnapshot& query,
                                           rust::Str candidate, std::uint8_t source) {
    if (!query.available || (source != 0 && source != 1)) return false;
    metasequoia::OnlineQuery request;
    request.scheme = static_cast<SchemeType>(query.scheme);
    request.generation = query.generation;
    request.identity = std::string(query.identity);
    request.query_text = std::string(query.query_text);
    request.cache_key = std::string(query.cache_key);
    for (const auto& segment : query.pinyin_segments)
        request.pinyin_segments.emplace_back(std::string(segment));
    request.cloud_eligible = query.cloud_eligible;
    request.ai_eligible = query.ai_eligible;
    request.session_id = query.session_id;
    const auto kind = source == 0 ? CandidateSource::CloudSuggestion
                                  : CandidateSource::AiSuggestion;
    return session_.apply_online_candidate(request, std::string(candidate), kind);
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
void EngineSession::set_paired_punctuation_enabled(bool enabled) {
    session_.set_paired_punctuation_enabled(enabled);
}
void EngineSession::set_punctuation_lock(std::uint8_t lock) {
    if (lock > 2) throw std::invalid_argument("Invalid punctuation lock");
    session_.set_punctuation_lock(static_cast<int>(lock));
}
void EngineSession::set_dedicated_english(bool enabled) {
    session_.set_dedicated_english(enabled);
}
}

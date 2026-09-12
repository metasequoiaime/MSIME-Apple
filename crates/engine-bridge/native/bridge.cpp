#include "bridge.h"
#include "msime-engine-bridge/src/lib.rs.h"
#include <metasequoia/personal_dictionary.h>
#include <metasequoia/handwriting.h>
#include <algorithm>
#include <metasequoia/dictionary_state.h>
#include <stdexcept>
#include <type_traits>
#include <limits>
#include <filesystem>
#include "../../vendor/MSIME-Engine/quanpin/quanpin_utils.h"
#include <sqlite3.h>
#include <unordered_set>
#include <memory>

namespace msime {
namespace {
metasequoia::RuntimePaths paths_for(const EngineOptions& value) {
    return {std::filesystem::u8path(std::string(value.resources)),
            std::filesystem::u8path(std::string(value.user_data)),
            std::filesystem::u8path(std::string(value.cache)),
            std::filesystem::u8path(std::string(value.dictionaries))};
}
void prepare_translation_sidecar(const EngineOptions& value) {
    const auto paths = paths_for(value);
    const auto name = std::filesystem::path("custom_translations.txt");
    const auto target = paths.dictionary(name);
    auto source = paths.user(name);
    std::error_code error;
    if (!std::filesystem::is_regular_file(source, error)) {
        error.clear();
        source = paths.resource(name);
    }
    if (std::filesystem::is_regular_file(source, error)) {
        error.clear();
        std::filesystem::create_directories(target.parent_path(), error);
        if (!error)
            std::filesystem::copy_file(source, target,
                                       std::filesystem::copy_options::overwrite_existing,
                                       error);
        if (error)
            throw std::runtime_error("Unable to prepare custom translation sidecar");
    } else {
        error.clear();
        std::filesystem::remove(target, error);
    }
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
    prepare_translation_sidecar(value);
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
    options.autocorrect_types =
        (value.autocorrect_transposition ? quanpin::kAutocorrectTransposition : 0u) |
        (value.autocorrect_neighbor ? quanpin::kAutocorrectNeighbor : 0u);
    options.chinese_punctuation = value.chinese_punctuation;
    options.paired_punctuation = value.paired_punctuation;
    options.punctuation_lock = value.punctuation_lock;
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
    options.local_modes = {value.local_unicode, value.local_date_time, value.local_quick_phrase, value.local_emoji,
                           value.local_kaomoji, value.local_super_jianpin, value.local_temporary_english,
                           value.local_temporary_japanese};
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
    shuangpin_profile_(options_for(options).shuangpin_profile.name) {}
std::unique_ptr<EngineSession> create_session(const EngineOptions& options) {
    return std::make_unique<EngineSession>(options);
}
// Framing matches Apple DictionaryStateRevision at 2b0250f4dd7012520392b310dfcc0288c3208a75.
void hash_dictionary_state(const EngineOptions& options, DictionaryRevision& sink) {
    metasequoia::stream_dictionary_state(paths_for(options), [&](const metasequoia::DictionaryStateRecord& record) {
        std::visit([&](const auto& value) {
            using T = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<T, metasequoia::DictionaryStateEntry>) {
                sink.text("entry");
                switch (value.kind) {
                case metasequoia::PersonalDictionaryKind::Pinyin: sink.text("pinyin"); break;
                case metasequoia::PersonalDictionaryKind::Wubi: sink.text("wubi"); break;
                case metasequoia::PersonalDictionaryKind::QuickPhrase: sink.text("quick"); break;
                case metasequoia::PersonalDictionaryKind::English: sink.text("english"); break;
                }
                sink.text(value.key); sink.text(value.value);
                sink.integer(static_cast<std::uint64_t>(value.weight));
                sink.text(value.display); sink.integer(value.deleted); sink.integer(value.user_inserted);
            } else {
                if constexpr (std::is_same_v<T, metasequoia::DictionaryStatePosition>) sink.text("position");
                else sink.text("selection");
                sink.text(value.context); sink.text(value.key); sink.text(value.value);
                if constexpr (std::is_same_v<T, metasequoia::DictionaryStatePosition>) sink.integer(value.position);
                else sink.integer(value.count);
            }
        }, record);
        return true;
    });
}
EngineOptions stage_dictionary_state(const EngineOptions& options, rust::Str generation,
    rust::Str content_id, std::size_t maximum_records, DictionaryRecordStream& stream) {
    if (maximum_records == 0) throw std::invalid_argument("Invalid snapshot record limit");
    const auto paths = metasequoia::stage_dictionary_state(
        std::filesystem::u8path(std::string(options.resources)),
        std::filesystem::u8path(std::string(generation)), std::string(content_id),
        [&](metasequoia::DictionaryStateRecord& output) {
            const auto value = stream.next(); // Transport failure throws; only verified EOF returns false.
            if (value.record_type == 0) return false;
            if (value.record_type == 1) {
                using Kind = metasequoia::PersonalDictionaryKind;
                Kind kind;
                switch (value.kind) {
                case DictionaryKind::Pinyin: kind = Kind::Pinyin; break;
                case DictionaryKind::Wubi: kind = Kind::Wubi; break;
                case DictionaryKind::QuickPhrase: kind = Kind::QuickPhrase; break;
                case DictionaryKind::English: kind = Kind::English; break;
                default: throw std::invalid_argument("Invalid snapshot dictionary kind");
                }
                output = metasequoia::DictionaryStateEntry{kind, std::string(value.key),
                    std::string(value.value), value.number, std::string(value.display),
                    value.deleted, value.user_inserted};
            } else if (value.record_type == 2) {
                if (value.number < std::numeric_limits<int>::min() || value.number > std::numeric_limits<int>::max())
                    throw std::invalid_argument("Invalid snapshot position");
                output = metasequoia::DictionaryStatePosition{std::string(value.context),
                    std::string(value.key), std::string(value.value), static_cast<int>(value.number)};
            } else if (value.record_type == 3) {
                if (value.number < std::numeric_limits<int>::min() || value.number > std::numeric_limits<int>::max())
                    throw std::invalid_argument("Invalid snapshot selection count");
                output = metasequoia::DictionaryStateSelection{std::string(value.context),
                    std::string(value.key), std::string(value.value), static_cast<int>(value.number)};
            } else throw std::invalid_argument("Invalid snapshot record type");
            return true;
        }, maximum_records);
    auto result = options;
    result.resources = paths.resources.u8string();
    result.user_data = paths.user_data.u8string();
    result.cache = paths.cache.u8string();
    result.dictionaries = paths.dictionaries.u8string();
    return result;
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
    return {paths.resources.u8string(), paths.user_data.u8string(), paths.cache.u8string(), paths.dictionaries.u8string(), 0, 0, false, true, true, true, "ziranma", true, true, 0, "promote", 1, 1, true, 2, false, false, true, true, true, true, true, true, true, true, true};
}
EngineSnapshot EngineSession::snapshot() const {
    auto value = session_.snapshot();
    EngineSnapshot output;
    output.local_mode = local_mode_name(value.local_mode);
    output.nine_key = nine_key_;
    for (const auto& spelling : value.nine_key_spellings)
        output.nine_key_spellings.push_back(rust::String(spelling));
    output.microsoft_shuangpin = microsoft_shuangpin_;
    output.scheme = static_cast<std::uint8_t>(value.scheme);
    output.shuangpin_profile = rust::String(shuangpin_profile_);
    output.answered_by_pinyin_fallback = value.answered_by_pinyin_fallback;
    output.preedit = value.preedit;
    output.editing_text = value.editing_text;
    output.caret_position = value.caret_position;
    for (std::size_t index = 0; index < value.candidates.size(); ++index) {
        const auto &candidate = value.candidates[index];
        output.candidates.push_back(rust::String(candidate.word));
        const auto &annotation = index < value.candidate_annotations.size()
                                     ? value.candidate_annotations[index]
                                     : candidate.corrected_from;
        output.candidate_annotations.push_back(rust::String(annotation));
        output.candidate_sources.push_back(static_cast<std::uint8_t>(candidate.source));
        output.candidate_positions.push_back(static_cast<std::uint8_t>(candidate.fixed_position));
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
rust::Vec<EmojiCatalogItem> emoji_catalog_page(rust::Str resources, rust::Str search,
                                               rust::Str category, std::size_t offset,
                                               std::uint16_t limit) {
    return emoji_catalog_filtered_page(resources, search, category, "", offset, limit, "");
}
rust::Vec<EmojiCatalogItem> emoji_catalog_filtered_page(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent) {
    rust::Vec<EmojiCatalogItem> result;
    if (limit == 0 || limit > 4096 || offset > static_cast<std::size_t>(std::numeric_limits<sqlite3_int64>::max()))
        throw std::invalid_argument("Invalid emoji catalog page");
    const auto path = std::filesystem::u8path(std::string(resources)) / "others.db";
    sqlite3 *database = nullptr;
    const int opened = sqlite3_open_v2(path.u8string().c_str(), &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nullptr);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database_guard(database, sqlite3_close);
    if (opened != SQLITE_OK)
        throw std::runtime_error("Emoji catalog unavailable");
    const std::string category_text(category);
    const std::string group_text(group);
    const std::string parent_text(parent);
    const bool kaomoji = category_text == "kaomoji";
    const bool symbols = category_text == "symbols";
    const char *sql = nullptr;
    if (kaomoji) {
        sql = "SELECT kaomoji,'All',keywords FROM kaomoji_catalog "
              "WHERE (?1 = '' OR kaomoji LIKE ?2 OR keywords LIKE ?2) "
              "AND (?5 = '' OR ?5 = 'All') "
              "ORDER BY sort_order LIMIT ?3 OFFSET ?4";
    } else if (symbols) {
        sql = "SELECT symbol,category,keywords FROM symbol_catalog "
              "WHERE (?1 = '' OR symbol LIKE ?2 OR category LIKE ?2 OR "
              "parent_category LIKE ?2 OR keywords LIKE ?2) "
              "AND (?5 = '' OR category = ?5) "
              "AND (?6 = '' OR COALESCE(NULLIF(parent_category,''),category) = ?6) "
              "ORDER BY sort_order LIMIT ?3 OFFSET ?4";
    } else {
        sql = "SELECT emoji,category,keywords FROM emoji "
              "WHERE (?1 = '' OR category = ?1) "
              "AND (?2 = '' OR pinyin LIKE ?3 OR keywords LIKE ?3 OR emoji LIKE ?3) "
              "ORDER BY sort_order LIMIT ?4 OFFSET ?5";
    }
    sqlite3_stmt *statement = nullptr;
    const int prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nullptr);
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement_guard(statement, sqlite3_finalize);
    if (prepared != SQLITE_OK)
        throw std::runtime_error("Emoji catalog query unavailable");
    // Do not include SQLite diagnostics: they can expose resource paths or data.
    const auto check_bind = [](int status) {
        if (status != SQLITE_OK)
            throw std::runtime_error("Emoji catalog query rejected");
    };
    const std::string search_text(search);
    const std::string pattern = "%" + search_text + "%";
    if (kaomoji || symbols) {
        check_bind(sqlite3_bind_text(statement, 1, search_text.c_str(), -1, SQLITE_TRANSIENT));
        check_bind(sqlite3_bind_text(statement, 2, pattern.c_str(), -1, SQLITE_TRANSIENT));
        check_bind(sqlite3_bind_int(statement, 3, limit));
        check_bind(sqlite3_bind_int64(statement, 4, static_cast<sqlite3_int64>(offset)));
        check_bind(sqlite3_bind_text(statement, 5, group_text.c_str(), -1, SQLITE_TRANSIENT));
        if (symbols) check_bind(sqlite3_bind_text(statement, 6, parent_text.c_str(), -1, SQLITE_TRANSIENT));
    } else {
        const auto &selected_group = group_text.empty() ? category_text : group_text;
        check_bind(sqlite3_bind_text(statement, 1, selected_group.c_str(), -1, SQLITE_TRANSIENT));
        check_bind(sqlite3_bind_text(statement, 2, search_text.c_str(), -1, SQLITE_TRANSIENT));
        check_bind(sqlite3_bind_text(statement, 3, pattern.c_str(), -1, SQLITE_TRANSIENT));
        check_bind(sqlite3_bind_int(statement, 4, limit));
        check_bind(sqlite3_bind_int64(statement, 5, static_cast<sqlite3_int64>(offset)));
    }
    std::unordered_set<std::string> seen;
    int status = SQLITE_OK;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        const auto *text = reinterpret_cast<const char *>(sqlite3_column_text(statement, 0));
        const auto *group = reinterpret_cast<const char *>(sqlite3_column_text(statement, 1));
        const auto *annotation = reinterpret_cast<const char *>(sqlite3_column_text(statement, 2));
        if (text && seen.insert(text).second)
            result.push_back({rust::String(text), rust::String(annotation ? annotation : ""),
                              rust::String(group ? group : "")});
    }
    if (status != SQLITE_DONE)
        throw std::runtime_error("Emoji catalog read failed");
    return result;
}
rust::Vec<EmojiCatalogItem> emoji_catalog(rust::Str resources, rust::Str search,
                                          rust::Str category, std::uint8_t limit) {
    return emoji_catalog_page(resources, search, category, 0, limit);
}
rust::Vec<rust::String> emoji_catalog_groups(rust::Str resources, rust::Str category) {
    const auto path = std::filesystem::u8path(std::string(resources)) / "others.db";
    sqlite3 *database = nullptr;
    const int opened = sqlite3_open_v2(path.u8string().c_str(), &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nullptr);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database_guard(database, sqlite3_close);
    if (opened != SQLITE_OK) throw std::runtime_error("Emoji catalog unavailable");
    const std::string kind(category);
    const char *sql = kind == "kaomoji"
        ? "SELECT 'All' FROM kaomoji_catalog LIMIT 1"
        : kind == "symbols"
            ? "SELECT category FROM symbol_catalog WHERE category IS NOT NULL AND category != '' GROUP BY category ORDER BY MIN(sort_order), category"
            : "SELECT category FROM emoji WHERE category IS NOT NULL AND category != '' GROUP BY category ORDER BY MIN(sort_order), category";
    sqlite3_stmt *statement = nullptr;
    const int prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nullptr);
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement_guard(statement, sqlite3_finalize);
    if (prepared != SQLITE_OK) throw std::runtime_error("Emoji catalog query unavailable");
    rust::Vec<rust::String> groups;
    int status = SQLITE_OK;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        const auto *value = reinterpret_cast<const char *>(sqlite3_column_text(statement, 0));
        if (value) groups.push_back(rust::String(value));
    }
    if (status != SQLITE_DONE) throw std::runtime_error("Emoji catalog read failed");
    return groups;
}
rust::Vec<EmojiSymbolGroup> emoji_symbol_groups(rust::Str resources) {
    const auto path = std::filesystem::u8path(std::string(resources)) / "others.db";
    sqlite3 *database = nullptr;
    const int opened = sqlite3_open_v2(path.u8string().c_str(), &database,
                                     SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nullptr);
    const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database_guard(database, sqlite3_close);
    if (opened != SQLITE_OK) throw std::runtime_error("Emoji catalog unavailable");
    const char *sql = "SELECT COALESCE(NULLIF(parent_category,''),category) AS parent, category "
        "FROM symbol_catalog WHERE category IS NOT NULL AND category != '' "
        "GROUP BY parent, category ORDER BY MIN(sort_order), parent, category";
    sqlite3_stmt *statement = nullptr;
    const int prepared = sqlite3_prepare_v2(database, sql, -1, &statement, nullptr);
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement_guard(statement, sqlite3_finalize);
    if (prepared != SQLITE_OK) throw std::runtime_error("Emoji catalog query unavailable");
    rust::Vec<EmojiSymbolGroup> groups;
    int status = SQLITE_OK;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        const auto *parent = reinterpret_cast<const char *>(sqlite3_column_text(statement, 0));
        const auto *title = reinterpret_cast<const char *>(sqlite3_column_text(statement, 1));
        if (parent && title) groups.push_back({rust::String(parent), rust::String(title)});
    }
    if (status != SQLITE_DONE) throw std::runtime_error("Emoji catalog read failed");
    return groups;
}
rust::Vec<rust::String> handwriting_recognize(rust::Str model_path,
                                               rust::Slice<const HandwritingPoint> points,
                                               float width, float height) {
    if (model_path.empty() || points.empty())
        return {};
    std::vector<metasequoia::handwriting::Stroke> strokes;
    std::uint32_t stroke_count = 0;
    for (const auto &point : points)
        stroke_count = std::max(stroke_count, point.stroke + 1);
    strokes.resize(stroke_count);
    for (const auto &point : points)
        strokes[point.stroke].push_back({point.x, point.y});
    metasequoia::handwriting::Recognizer recognizer{std::string(model_path)};
    const auto candidates = recognizer.recognize(strokes, width, height);
    rust::Vec<rust::String> result;
    for (const auto &candidate : candidates)
        result.push_back(rust::String(candidate));
    return result;
}
EngineResult EngineSession::character(std::uint8_t value, bool shift) {
    if (value > 127) throw std::invalid_argument("Engine character must be ASCII");
    return result_for(session_.character(static_cast<char>(value), shift));
}
void EngineSession::set_nine_key_enabled(bool enabled) {
    session_.set_nine_key_enabled(enabled);
    nine_key_ = enabled;
}
EngineResult EngineSession::choose_nine_key_spelling(std::size_t index) {
    return result_for(session_.choose_nine_key_spelling(index));
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
EngineResult EngineSession::fix_candidate_position(std::size_t index, std::uint8_t position) {
    if (position < 1 || position > 5)
        throw std::invalid_argument("Invalid candidate position");
    return result_for(session_.fix_position(index, position));
}
EngineResult EngineSession::clear_candidate_position(std::size_t index) {
    return result_for(session_.clear_position(index));
}
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

void EngineSession::set_punctuation_lock(std::uint8_t lock) {
    session_.set_punctuation_lock(lock);
}

void EngineSession::set_paired_punctuation_enabled(bool enabled) { session_.set_paired_punctuation_enabled(enabled); }

void EngineSession::set_dedicated_english(bool enabled) {
    session_.set_dedicated_english(enabled);
}
}

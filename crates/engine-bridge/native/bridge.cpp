#include "bridge.h"
#include "msime-engine-bridge/src/lib.rs.h"
#include <metasequoia/personal_dictionary.h>
#include <metasequoia/handwriting.h>
#include <algorithm>
#include <cstdint>
#include <metasequoia/dictionary_state.h>
#include <stdexcept>
#include <type_traits>
#include <limits>
#include <filesystem>
#include "../../vendor/MSIME-Engine/contracts/assets/assets.h"
#include "../../vendor/MSIME-Engine/quanpin/quanpin_utils.h"
#include <sqlite3.h>
#include <unordered_map>
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
bool next_utf8(const std::string& text, std::size_t& offset, std::string& character,
               std::uint32_t& codepoint) {
    if (offset >= text.size()) return false;
    const auto first = static_cast<unsigned char>(text[offset]);
    std::size_t width = 0;
    if (first <= 0x7f) width = 1;
    else if (first >= 0xc2 && first <= 0xdf) width = 2;
    else if (first >= 0xe0 && first <= 0xef) width = 3;
    else if (first >= 0xf0 && first <= 0xf4) width = 4;
    else return false;
    if (offset + width > text.size()) return false;
    codepoint = first & (width == 1 ? 0x7f : width == 2 ? 0x1f : width == 3 ? 0x0f : 0x07);
    for (std::size_t index = 1; index < width; ++index) {
        const auto byte = static_cast<unsigned char>(text[offset + index]);
        if ((byte & 0xc0) != 0x80) return false;
        codepoint = (codepoint << 6) | (byte & 0x3f);
    }
    if ((width == 3 && codepoint < 0x800) || (width == 4 && codepoint < 0x10000) ||
        (codepoint >= 0xd800 && codepoint <= 0xdfff) || codepoint > 0x10ffff)
        return false;
    character.assign(text, offset, width);
    offset += width;
    return true;
}
bool is_han(std::uint32_t codepoint) {
    return (codepoint >= 0x3400 && codepoint <= 0x4dbf) ||
           (codepoint >= 0x4e00 && codepoint <= 0x9fff) ||
           (codepoint >= 0xf900 && codepoint <= 0xfaff) ||
           (codepoint >= 0x20000 && codepoint <= 0x2fa1f);
}
std::unordered_map<std::string, std::string> single_hanzi_map(sqlite3* database) {
    std::unordered_map<std::string, std::string> result;
    for (char initial = 'a'; initial <= 'z'; ++initial) {
        const auto table = std::string("tbl_1_") + initial;
        const auto sql = "SELECT \"key\", \"value\" FROM \"" + table +
                         "\" ORDER BY \"weight\" DESC, \"key\" ASC";
        sqlite3_stmt* statement = nullptr;
        if (sqlite3_prepare_v2(database, sql.c_str(), -1, &statement, nullptr) != SQLITE_OK)
            continue;
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const auto* key = reinterpret_cast<const char*>(sqlite3_column_text(statement, 0));
            const auto* value = reinterpret_cast<const char*>(sqlite3_column_text(statement, 1));
            if (key && value && result.find(value) == result.end()) result.emplace(value, key);
        }
        sqlite3_finalize(statement);
    }
    return result;
}
std::string exact_hanzi_pinyin(sqlite3* database, const std::string& word, std::size_t length) {
    for (char initial = 'a'; initial <= 'z'; ++initial) {
        const auto table = "tbl_" + std::to_string(length) + "_" + initial;
        const auto sql = "SELECT \"key\" FROM \"" + table +
                         "\" WHERE \"value\"=?1 ORDER BY \"weight\" DESC, \"key\" ASC LIMIT 1";
        sqlite3_stmt* statement = nullptr;
        if (sqlite3_prepare_v2(database, sql.c_str(), -1, &statement, nullptr) != SQLITE_OK)
            continue;
        sqlite3_bind_text(statement, 1, word.c_str(), static_cast<int>(word.size()), SQLITE_TRANSIENT);
        if (sqlite3_step(statement) == SQLITE_ROW) {
            const auto* key = reinterpret_cast<const char*>(sqlite3_column_text(statement, 0));
            if (key) {
                const std::string result(key);
                sqlite3_finalize(statement);
                return result;
            }
        }
        sqlite3_finalize(statement);
    }
    return {};
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
    options.fuzzy_pinyin.rules = value.fuzzy_pinyin_rules & 0x7ffu;
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
    shuangpin_profile_(options_for(options).shuangpin_profile.name),
    helpcode_keymap_(options.helpcode
                         ? HelpcodeUtils::load_helpcode_keymap(
                               std::filesystem::u8path(std::string(options.resources)),
                               std::string(options.helpcode_schema))
                         : nullptr),
    helpcode_enabled_(options.helpcode) {}
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
    EngineOptions result;
    result.resources = paths.resources.u8string();
    result.user_data = paths.user_data.u8string();
    result.cache = paths.cache.u8string();
    result.dictionaries = paths.dictionaries.u8string();
    result.scheme = 0;
    result.shuangpin_profile = 0;
    result.learning = false;
    result.autocorrect_transposition = true;
    result.autocorrect_neighbor = true;
    result.fuzzy_pinyin_rules = 0;
    result.helpcode = true;
    result.helpcode_schema = "ziranma";
    result.chinese_punctuation = true;
    result.paired_punctuation = true;
    result.punctuation_lock = 0;
    result.frequency_mode = "promote";
    result.frequency_trigger_count = 1;
    result.frequency_linear_step = 1;
    result.mixed_english = true;
    result.english_minimum_prefix = 2;
    result.mixed_emoji = false;
    result.mixed_kaomoji = false;
    result.local_unicode = true;
    result.local_date_time = true;
    result.local_quick_phrase = true;
    result.local_emoji = true;
    result.local_kaomoji = true;
    result.local_super_jianpin = true;
    result.local_temporary_english = true;
    result.local_temporary_japanese = true;
    return result;
}
rust::String hanzi_to_pinyin(const EngineOptions& options, rust::Str text) {
    const std::string word(text);
    if (word.empty()) return {};
    std::size_t offset = 0;
    std::size_t length = 0;
    while (offset < word.size()) {
        std::string character;
        std::uint32_t codepoint = 0;
        if (!next_utf8(word, offset, character, codepoint) || !is_han(codepoint)) return {};
        ++length;
    }
    if (length == 0 || length > 128) return {};
    const auto database_path = paths_for(options).dictionary(metasequoia::assets::main_dictionary);
    sqlite3* database = nullptr;
    if (sqlite3_open_v2(database_path.u8string().c_str(), &database,
                        SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nullptr) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return {};
    }
    std::string result = exact_hanzi_pinyin(database, word, length);
    if (result.empty()) {
        const auto singles = single_hanzi_map(database);
        offset = 0;
        while (offset < word.size()) {
            std::string character;
            std::uint32_t codepoint = 0;
            if (!next_utf8(word, offset, character, codepoint)) {
                result.clear();
                break;
            }
            const auto found = singles.find(character);
            if (found == singles.end()) {
                result.clear();
                break;
            }
            if (!result.empty()) result.push_back('\'');
            result += found->second;
        }
    }
    sqlite3_close(database);
    return result;
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
        auto annotation = index < value.candidate_annotations.size()
                              ? value.candidate_annotations[index]
                              : candidate.corrected_from;
        if (annotation.empty() && helpcode_enabled_ && helpcode_keymap_ &&
            candidate.source == CandidateSource::Generated &&
            (value.scheme == SchemeType::Quanpin || value.scheme == SchemeType::Shuangpin)) {
            annotation = HelpcodeUtils::compute_helpcodes(
                candidate.word, value.scheme == SchemeType::Quanpin, helpcode_keymap_.get());
        }
        output.candidate_annotations.push_back(rust::String(annotation));
        output.candidate_sources.push_back(static_cast<std::uint8_t>(candidate.source));
        output.candidate_positions.push_back(static_cast<std::uint8_t>(candidate.fixed_position));
        output.candidate_corrected.push_back(!candidate.corrected_from.empty());
    }
    return output;
}
void EngineSession::reset_cache() {
    session_.reset_cache();
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
static EmojiCatalogSlice read_emoji_catalog_slice(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent,
    bool deduplicate) {
    EmojiCatalogSlice result;
    result.next_offset = offset;
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
        if (result.next_offset == static_cast<std::size_t>(std::numeric_limits<sqlite3_int64>::max()))
            throw std::invalid_argument("Invalid emoji catalog cursor");
        ++result.next_offset;
        const auto *text = reinterpret_cast<const char *>(sqlite3_column_text(statement, 0));
        const auto *group = reinterpret_cast<const char *>(sqlite3_column_text(statement, 1));
        const auto *annotation = reinterpret_cast<const char *>(sqlite3_column_text(statement, 2));
        if (!deduplicate && (!text || !text[0] || (!kaomoji && (!group || !group[0]))))
            continue;
        if (text && (!deduplicate || seen.insert(text).second))
            result.items.push_back({rust::String(text), rust::String(annotation ? annotation : ""),
                              rust::String(group ? group : "")});
    }
    if (status != SQLITE_DONE)
        throw std::runtime_error("Emoji catalog read failed");
    result.complete = result.next_offset - offset < limit;
    return result;
}
rust::Vec<EmojiCatalogItem> emoji_catalog_filtered_page(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent) {
    return read_emoji_catalog_slice(resources, search, category, group, offset, limit, parent, true).items;
}
EmojiCatalogSlice emoji_catalog_slice(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent) {
    return read_emoji_catalog_slice(resources, search, category, group, offset, limit, parent, false);
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

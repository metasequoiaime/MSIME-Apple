#pragma once
#include "rust/cxx.h"
#include <memory>
#include <metasequoia/session.h>
#include "../../vendor/MSIME-Engine/common/helpcode_utils.h"

namespace msime {
struct EngineOptions;
struct DictionaryRevision;
struct DictionaryRecordStream;
EngineOptions stage_dictionary_state(const EngineOptions& options, rust::Str generation,
    rust::Str content_id, std::size_t maximum_records, DictionaryRecordStream& stream);
void hash_dictionary_state(const EngineOptions& options, DictionaryRevision& sink);
struct EngineSnapshot;
struct EngineResult;
struct OnlineQuerySnapshot;
struct EmojiCatalogItem;
struct EmojiCatalogSlice;
struct EmojiSymbolGroup;
struct HandwritingPoint;
struct DictionaryEntry;
struct DictionaryPage;
class EngineSession {
public:
    explicit EngineSession(const EngineOptions& options);
    EngineSnapshot snapshot() const;
    OnlineQuerySnapshot online_query() const;
    bool apply_online_candidate(const OnlineQuerySnapshot& query, rust::Str candidate,
                                std::uint8_t source);
    EngineResult character(std::uint8_t value, bool shift);
    void set_nine_key_enabled(bool enabled);
    EngineResult choose_nine_key_spelling(std::size_t index);
    EngineResult command(std::uint8_t value);
    EngineResult select(std::size_t index);
    EngineResult pin_candidate(std::size_t index);
    EngineResult remove_candidate(std::size_t index);
    EngineResult fix_candidate_position(std::size_t index, std::uint8_t position);
    EngineResult clear_candidate_position(std::size_t index);
    EngineResult select_edge(std::size_t index, std::uint8_t edge);
    EngineResult finish(std::size_t index);
    EngineResult punctuation(std::uint8_t value);
    void set_chinese_punctuation_enabled(bool enabled);
    void set_punctuation_lock(std::uint8_t lock);
    void set_paired_punctuation_enabled(bool enabled);
    void set_dedicated_english(bool enabled);
private:
    metasequoia::Session session_;
    bool nine_key_ = false;
    bool microsoft_shuangpin_;
    std::string shuangpin_profile_;
    HelpcodeUtils::SharedKeymap helpcode_keymap_;
    bool helpcode_enabled_ = false;
};
std::unique_ptr<EngineSession> create_session(const EngineOptions& options);
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id);
rust::String hanzi_to_pinyin(const EngineOptions& options, rust::Str text);
DictionaryPage dictionary_entries(const EngineOptions& options, std::size_t offset, std::size_t limit);
void dictionary_edit(const EngineOptions& options, rust::Slice<const DictionaryEntry> previous,
                     rust::Slice<const DictionaryEntry> replacement, rust::Str request_id);
rust::Vec<EmojiCatalogItem> emoji_catalog(rust::Str resources, rust::Str search,
                                          rust::Str category, std::uint8_t limit);
rust::Vec<EmojiCatalogItem> emoji_catalog_page(rust::Str resources, rust::Str search,
                                               rust::Str category, std::size_t offset,
                                               std::uint16_t limit);
rust::Vec<EmojiCatalogItem> emoji_catalog_filtered_page(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent);
EmojiCatalogSlice emoji_catalog_slice(rust::Str resources, rust::Str search,
    rust::Str category, rust::Str group, std::size_t offset, std::uint16_t limit, rust::Str parent);
rust::Vec<EmojiSymbolGroup> emoji_symbol_groups(rust::Str resources);
rust::Vec<rust::String> emoji_catalog_groups(rust::Str resources, rust::Str category);
rust::Vec<rust::String> handwriting_recognize(rust::Str model_path,
                                               rust::Slice<const HandwritingPoint> points,
                                               float width, float height);
}

#pragma once
#include "rust/cxx.h"
#include <memory>
#include <metasequoia/session.h>
#include "common/helpcode_utils.h"

namespace msime {
struct EngineOptions;
struct EngineSnapshot;
struct EngineResult;
struct OnlineQuerySnapshot;
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
    EngineResult command(std::uint8_t value);
    EngineResult select(std::size_t index);
    EngineResult select_edge(std::size_t index, std::uint8_t edge);
    EngineResult finish(std::size_t index);
    EngineResult punctuation(std::uint8_t value);
    void set_chinese_punctuation_enabled(bool enabled);
private:
    metasequoia::Session session_;
    bool microsoft_shuangpin_;
    std::string shuangpin_profile_;
    HelpcodeUtils::SharedKeymap helpcode_keymap_;
};
std::unique_ptr<EngineSession> create_session(const EngineOptions& options);
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id);
DictionaryPage dictionary_entries(const EngineOptions& options, std::size_t offset, std::size_t limit);
void dictionary_edit(const EngineOptions& options, rust::Slice<const DictionaryEntry> previous,
                     rust::Slice<const DictionaryEntry> replacement, rust::Str request_id);
}

#pragma once
#include "rust/cxx.h"
#include <memory>
#include <metasequoia/session.h>

namespace msime {
struct EngineOptions;
struct DictionaryStateRecord;
EngineOptions stage_dictionary_state(rust::Str resources, rust::Str generation, rust::Str content_id,
                                     const rust::Vec<DictionaryStateRecord> &records);
struct EngineOptions;
struct EngineSnapshot;
struct EngineResult;
struct OnlineQuerySnapshot;
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
    EngineResult pin_candidate(std::size_t index);
    EngineResult remove_candidate(std::size_t index);
    EngineResult select_edge(std::size_t index, std::uint8_t edge);
    EngineResult finish(std::size_t index);
    EngineResult punctuation(std::uint8_t value);
    void set_chinese_punctuation_enabled(bool enabled);
private:
    metasequoia::Session session_;
    bool microsoft_shuangpin_;
};
rust::String validate_personal_dictionary(std::uint8_t kind, rust::Str key, rust::Str value);
std::unique_ptr<EngineSession> create_session(const EngineOptions& options);
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id);
}

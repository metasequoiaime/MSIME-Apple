#include "bridge.h"
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
    options.learning = value.learning;
    options.chinese_punctuation = value.chinese_punctuation;
    options.helpcode = false;
    return options;
}
EngineResult result_for(const metasequoia::KeyResult& value) {
    return {value.handled, value.commit.has_value(), value.commit.value_or(""), value.diagnostic.value_or("")};
}
}
EngineSession::EngineSession(const EngineOptions& options) : session_(options_for(options)) {}
std::unique_ptr<EngineSession> create_session(const EngineOptions& options) {
    return std::make_unique<EngineSession>(options);
}
EngineOptions prepare_options(rust::Str resources, rust::Str user_data, rust::Str cache, rust::Str content_id) {
    auto paths = metasequoia::prepare_runtime_paths(std::filesystem::u8path(std::string(resources)),
        std::filesystem::u8path(std::string(user_data)), std::filesystem::u8path(std::string(cache)), std::string(content_id));
    return {paths.resources.u8string(), paths.user_data.u8string(), paths.cache.u8string(), paths.dictionaries.u8string(), 0, false, true};
}
EngineSnapshot EngineSession::snapshot() const {
    auto value = session_.snapshot();
    EngineSnapshot output;
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
EngineResult EngineSession::finish(std::size_t index) { return result_for(session_.finish(index)); }
EngineResult EngineSession::punctuation(std::uint8_t value) {
    if (value > 127) throw std::invalid_argument("Engine punctuation must be ASCII");
    return result_for(session_.punctuation(static_cast<char>(value)));
}
}

#include "CandidateTranslation.h"

#include "english/english_dictionary.h"

#include <chrono>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

std::filesystem::path MakeGlossDatabase()
{
    const auto path = std::filesystem::temp_directory_path() /
                      ("metasequoia-candidate-translation-" +
                       std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count()) + ".db");
    std::filesystem::remove(path);
    Require(EnglishDictionary::ensure_schema(path.string()), "Failed to create the gloss fixture.");
    Require(EnglishDictionary::upsert_gloss(path.string(), true, "水杉", "metasequoia; dawn redwood; extra"),
            "Failed to insert a Chinese gloss.");
    Require(EnglishDictionary::upsert_gloss(path.string(), false, "hello", "你好；问候"),
            "Failed to insert an English gloss.");
    return path;
}
} // namespace

int main()
{
    Require(metasequoia::mac::FormatCandidateGloss("  hello   world \n") == "hello world",
            "Whitespace in a gloss was not collapsed.");
    Require(metasequoia::mac::FormatCandidateGloss("   ").empty(), "A blank gloss was treated as visible text.");
    Require(metasequoia::mac::FormatCandidateGloss("metasequoia; dawn redwood; extra") == "metasequoia; dawn redwood",
            "A gloss kept more than two senses.");
    Require(metasequoia::mac::FormatCandidateGloss("你好；问候；招呼") == "你好; 问候",
            "A Chinese-delimited gloss kept more than two senses.");
    Require(metasequoia::mac::FormatCandidateGloss("开会；聚会") == "开会; 聚会",
            "A gloss was split on UTF-8 bytes inside 会.");
    Require(metasequoia::mac::FormatCandidateGloss("问候；招呼；你好") == "问候; 招呼",
            "A gloss was split on UTF-8 bytes inside 招.");

    WordItem chinese{"shui'shan", "水杉", 1};
    const auto chineseQuery = metasequoia::mac::TranslationQueryForCandidate(chinese);
    Require(chineseQuery.has_value() && chineseQuery->key == "水杉" &&
                chineseQuery->direction == metasequoia::mac::TranslationDirection::ChineseToEnglish,
            "A Chinese candidate did not request an English gloss.");

    WordItem english{"hello", "Hello", 1, CandidateSource::EnglishDictionary};
    const auto englishQuery = metasequoia::mac::TranslationQueryForCandidate(english);
    Require(englishQuery.has_value() && englishQuery->key == "hello" &&
                englishQuery->direction == metasequoia::mac::TranslationDirection::EnglishToChinese,
            "An English dictionary candidate did not request a Chinese gloss.");

    WordItem ascii{"", "OpenAI", 1};
    const auto asciiQuery = metasequoia::mac::TranslationQueryForCandidate(ascii);
    Require(asciiQuery.has_value() && asciiQuery->key == "openai" &&
                asciiQuery->direction == metasequoia::mac::TranslationDirection::EnglishToChinese,
            "An ASCII candidate did not normalize to an English gloss query.");

    WordItem emoji{"", "😀", 1, CandidateSource::Emoji};
    Require(!metasequoia::mac::TranslationQueryForCandidate(emoji).has_value(),
            "An emoji candidate requested a gloss.");

    const auto path = MakeGlossDatabase();
    EnglishDictionary dictionary(path.string(), false);
    Require(metasequoia::mac::LookupCandidateGloss(dictionary, *chineseQuery) == "metasequoia; dawn redwood",
            "The local Chinese gloss was not formatted for the candidate window.");
    Require(metasequoia::mac::LookupCandidateGloss(dictionary, *englishQuery) == "你好; 问候",
            "The local English gloss was not formatted for the candidate window.");
    std::filesystem::remove(path);
    return 0;
}

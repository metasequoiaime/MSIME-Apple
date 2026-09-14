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

    // 只有含汉字的候选能联网翻译。拼音缓冲和纯 ASCII 串送上去既拿不到有意义的释义(生产库里
    // `bag→bag`、`for→for` 这类占了 44 行),又把用户的原始按键序列发给第三方服务商 —— 其中一条是
    // `cun` 再按一个 t 拼成的英文脏词,原样进了共享缓存。
    Require(metasequoia::mac::CandidateSupportsOnlineGloss(chinese), "A Chinese candidate was refused online gloss.");
    for (const char *raw : {"cun", "cunt", "bag", "for", "zip", "ti", "err", "OpenAI", "123"})
    {
        WordItem buffered{"", raw, 1};
        Require(!metasequoia::mac::CandidateSupportsOnlineGloss(buffered),
                "An ASCII candidate was sent to the online translator.");
    }
    Require(!metasequoia::mac::CandidateSupportsOnlineGloss(emoji), "An emoji candidate was sent to the translator.");
    Require(!metasequoia::mac::CandidateSupportsOnlineGloss(english),
            "An English dictionary candidate was sent to the online translator instead of using local ECDICT.");

    const auto path = MakeGlossDatabase();
    EnglishDictionary dictionary(path.string(), false);
    Require(metasequoia::mac::LookupCandidateGloss(dictionary, *chineseQuery) == "metasequoia; dawn redwood",
            "The local Chinese gloss was not formatted for the candidate window.");
    Require(metasequoia::mac::LookupCandidateGloss(dictionary, *englishQuery) == "你好; 问候",
            "The local English gloss was not formatted for the candidate window.");

    // 联网补回来的释义要活过重启。缓存是独立的用户文件,随包发的词库(上面那个 path)不动。
    const auto cachePath = path.string() + ".cache";
    std::filesystem::remove(cachePath);
    {
        EnglishDictionary session(path.string(), false, "", cachePath);
        const WordItem missing{"", "光合作用", 1};
        const auto query = metasequoia::mac::TranslationQueryForCandidate(missing);
        Require(query.has_value() && query->direction == metasequoia::mac::TranslationDirection::ChineseToEnglish,
                "A Chinese candidate did not request an English gloss.");
        Require(metasequoia::mac::LookupCandidateGloss(session, *query).empty(),
                "A gloss appeared before anything was fetched for it.");
        Require(session.cache_gloss(true, query->key, "photosynthesis"), "Persisting a fetched gloss failed.");
        Require(metasequoia::mac::LookupCandidateGloss(session, *query) == "photosynthesis",
                "A freshly persisted gloss was not visible to the same session.");
        // 随包发的那份仍然压过缓存:缓存里装的是词库答不上来的词,质量最没保证。
        Require(metasequoia::mac::LookupCandidateGloss(session, *chineseQuery) == "metasequoia; dawn redwood",
                "The cache overrode a shipped gloss.");
    }
    {
        // 新开一个实例 = 下次开机。缓存文件还在,释义就还在。
        EnglishDictionary restarted(path.string(), false, "", cachePath);
        const WordItem missing{"", "光合作用", 1};
        const auto query = metasequoia::mac::TranslationQueryForCandidate(missing);
        Require(metasequoia::mac::LookupCandidateGloss(restarted, *query) == "photosynthesis",
                "A persisted gloss did not survive a restart.");
    }
    {
        // 没有缓存文件的实例照常工作,不会因为缺文件而失败。
        EnglishDictionary withoutCache(path.string(), false);
        const WordItem missing{"", "光合作用", 1};
        Require(metasequoia::mac::LookupCandidateGloss(withoutCache,
                                                       *metasequoia::mac::TranslationQueryForCandidate(missing))
                    .empty(),
                "A session without a cache path read someone else's cache.");
    }
    std::filesystem::remove(cachePath);
    std::filesystem::remove(path);
    return 0;
}

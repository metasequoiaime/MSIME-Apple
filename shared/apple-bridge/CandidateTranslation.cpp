#include "CandidateTranslation.h"

#include "common/helpcode_utils.h"
#include "english/english_dictionary.h"

#include <string_view>
#include <vector>

namespace metasequoia::mac
{
namespace
{
bool IsAsciiSpace(unsigned char ch)
{
    return ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n';
}

// 汉字码点范围:统一表意文字、扩展 A、兼容表意文字,以及扩展 B 起的增补平面。
bool IsHanCodePoint(char32_t code)
{
    return (code >= 0x4E00 && code <= 0x9FFF) || (code >= 0x3400 && code <= 0x4DBF) ||
           (code >= 0xF900 && code <= 0xFAFF) || (code >= 0x20000 && code <= 0x3FFFF);
}

std::string CollapseWhitespace(const std::string &text)
{
    std::string out;
    out.reserve(text.size());
    bool pending_space = false;
    for (const unsigned char ch : text)
    {
        if (IsAsciiSpace(ch))
        {
            pending_space = !out.empty();
            continue;
        }
        if (pending_space)
        {
            out.push_back(' ');
            pending_space = false;
        }
        out.push_back(static_cast<char>(ch));
    }
    return out;
}

size_t FindSenseDelimiter(const std::string &text, size_t begin, size_t &delimiter_size)
{
    constexpr std::string_view kAsciiDelimiter = ";";
    constexpr std::string_view kFullwidthDelimiter = "；";
    const size_t ascii = text.find(kAsciiDelimiter, begin);
    const size_t fullwidth = text.find(kFullwidthDelimiter, begin);
    if (ascii == std::string::npos && fullwidth == std::string::npos)
    {
        delimiter_size = 0;
        return std::string::npos;
    }
    if (fullwidth == std::string::npos || (ascii != std::string::npos && ascii < fullwidth))
    {
        delimiter_size = kAsciiDelimiter.size();
        return ascii;
    }
    delimiter_size = kFullwidthDelimiter.size();
    return fullwidth;
}

std::string TakeLeadingSenses(const std::string &text, size_t limit)
{
    if (limit == 0 || text.empty())
        return {};
    std::vector<std::string> senses;
    size_t begin = 0;
    while (begin <= text.size() && senses.size() < limit)
    {
        size_t delimiter_size = 0;
        const size_t end = FindSenseDelimiter(text, begin, delimiter_size);
        const size_t stop = end == std::string::npos ? text.size() : end;
        std::string sense = CollapseWhitespace(text.substr(begin, stop - begin));
        if (!sense.empty())
            senses.push_back(std::move(sense));
        if (end == std::string::npos)
            break;
        begin = end + delimiter_size;
    }
    std::string joined;
    for (size_t index = 0; index < senses.size(); ++index)
    {
        if (index > 0)
            joined += "; ";
        joined += senses[index];
    }
    return joined;
}

bool IsEnglishCandidateText(const std::string &visible, std::string &normalized)
{
    bool has_ascii_letter = false;
    normalized.clear();
    normalized.reserve(visible.size());
    for (const unsigned char ch : visible)
    {
        if (ch >= 'A' && ch <= 'Z')
        {
            normalized.push_back(static_cast<char>(ch + ('a' - 'A')));
            has_ascii_letter = true;
        }
        else if (ch >= 'a' && ch <= 'z')
        {
            normalized.push_back(static_cast<char>(ch));
            has_ascii_letter = true;
        }
        else if (ch == ' ' || ch == '-' || ch == '\'')
        {
            normalized.push_back(static_cast<char>(ch));
        }
        else
        {
            return false;
        }
    }
    return has_ascii_letter;
}
} // namespace

std::optional<TranslationQuery> TranslationQueryForCandidate(const WordItem &item)
{
    if (item.word.empty() || item.source == CandidateSource::Emoji || item.source == CandidateSource::Kaomoji)
        return std::nullopt;
    if (item.source == CandidateSource::EnglishDictionary && !item.pinyin.empty())
        return TranslationQuery{item.pinyin, TranslationDirection::EnglishToChinese};

    std::string normalized;
    if (IsEnglishCandidateText(item.word, normalized))
        return TranslationQuery{std::move(normalized), TranslationDirection::EnglishToChinese};
    if (HelpcodeUtils::count_han_chars(item.word) > 0)
        return TranslationQuery{item.word, TranslationDirection::ChineseToEnglish};
    return std::nullopt;
}

bool CandidateSupportsOnlineGloss(const WordItem &item)
{
    // 注意不要用 HelpcodeUtils::count_han_chars —— 它名不副实,数的是 UTF-8 码点总数而不是汉字数,
    // 对 "cun"、"123"、"OpenAI" 一律返回大于 0。这里必须真的按码点范围判断。
    const auto &word = item.word;
    for (std::size_t i = 0; i < word.size();)
    {
        const auto lead = static_cast<unsigned char>(word[i]);
        std::size_t width = 1;
        char32_t code = lead;
        if (lead >= 0xF0)
        {
            width = 4;
            code = lead & 0x07u;
        }
        else if (lead >= 0xE0)
        {
            width = 3;
            code = lead & 0x0Fu;
        }
        else if (lead >= 0xC0)
        {
            width = 2;
            code = lead & 0x1Fu;
        }
        if (i + width > word.size())
            return false;
        for (std::size_t k = 1; k < width; ++k)
            code = (code << 6) | (static_cast<unsigned char>(word[i + k]) & 0x3Fu);
        if (IsHanCodePoint(code))
            return true;
        i += width;
    }
    return false;
}

std::string FormatCandidateGloss(const std::string &text)
{
    return TakeLeadingSenses(text, 2);
}

std::string LookupCandidateGloss(EnglishDictionary &dictionary, const TranslationQuery &query)
{
    if (query.key.empty())
        return {};
    const std::string raw = query.direction == TranslationDirection::EnglishToChinese
                                ? dictionary.query_chinese_gloss(query.key)
                                : dictionary.query_english_gloss(query.key);
    return FormatCandidateGloss(raw);
}
} // namespace metasequoia::mac

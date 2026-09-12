#pragma once

#include "core/word_item.h"

#include <optional>
#include <string>

class EnglishDictionary;

namespace metasequoia::mac
{
enum class TranslationDirection
{
    ChineseToEnglish,
    EnglishToChinese,
};

struct TranslationQuery
{
    std::string key;
    TranslationDirection direction = TranslationDirection::ChineseToEnglish;
};

std::optional<TranslationQuery> TranslationQueryForCandidate(const WordItem &item);
std::string FormatCandidateGloss(const std::string &text);
std::string LookupCandidateGloss(EnglishDictionary &dictionary, const TranslationQuery &query);
} // namespace metasequoia::mac

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

// 这个候选能不能送去联网翻译。只有含汉字的可以 —— 在线这条路问的是「这个中文词译成目标语言是什么」,
// 拼音缓冲和纯 ASCII 串送进去没有意义,而且会把用户的原始按键序列发给第三方服务商。英文候选的中文
// 释义由本机 ECDICT 负责,不该走网络。
bool CandidateSupportsOnlineGloss(const WordItem &item);
std::string FormatCandidateGloss(const std::string &text);
std::string LookupCandidateGloss(EnglishDictionary &dictionary, const TranslationQuery &query);
} // namespace metasequoia::mac

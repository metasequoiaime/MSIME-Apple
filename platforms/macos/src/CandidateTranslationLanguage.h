#pragma once

#include <cstddef>

namespace metasequoia::mac
{
// The languages a candidate can be glossed into. `code` is what the phrase-based services take;
// `name` is what the model is asked for, since a model reads "Spanish" and not "ES". The machine
// translation providers accept every code here, so one list serves all three.
struct CandidateTranslationLanguage
{
    const char *title;
    const char *code;
    const char *name;
};

inline constexpr CandidateTranslationLanguage kCandidateTranslationLanguages[] = {
    {"英语", "EN", "English"},     {"日语", "JA", "Japanese"}, {"韩语", "KO", "Korean"},
    {"西班牙语", "ES", "Spanish"}, {"法语", "FR", "French"},   {"德语", "DE", "German"},
};

inline constexpr std::size_t kCandidateTranslationLanguageCount =
    sizeof(kCandidateTranslationLanguages) / sizeof(kCandidateTranslationLanguages[0]);

// A stored index out of range answers with the first language rather than reading past the table.
// The list has grown once and will again; a preference written by a later build must not decide
// what an earlier one indexes into.
inline const CandidateTranslationLanguage &CandidateTranslationLanguageAt(std::size_t index)
{
    return kCandidateTranslationLanguages[index < kCandidateTranslationLanguageCount ? index : 0];
}

// The providers a translation can come from. The account's model is the one that needs no keys of
// the user's own, so it leads.
enum class CandidateTranslationProvider
{
    AccountModel,
    TencentMachineTranslation,
    DeepLX,
};

inline CandidateTranslationProvider CandidateTranslationProviderAt(std::size_t index)
{
    switch (index)
    {
    case 1:
        return CandidateTranslationProvider::TencentMachineTranslation;
    case 2:
        return CandidateTranslationProvider::DeepLX;
    default:
        return CandidateTranslationProvider::AccountModel;
    }
}
} // namespace metasequoia::mac

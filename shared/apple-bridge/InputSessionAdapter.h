#pragma once

#include <metasequoia/personal_dictionary.h>
#include <metasequoia/session.h>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class EnglishDictionary;

namespace metasequoia
{
struct RuntimePaths;
}

namespace metasequoia::apple
{
enum class CandidateAction
{
    Promote,
    Remove,
    FixFirst,
    ClearPosition
};
struct InputSnapshot
{
    bool handled = false;
    std::optional<std::string> commit;
    std::string preedit;
    std::vector<std::string> candidates;
    // The dictionary key each candidate was found by, in the same order. A wubi frontend needs it to
    // say which keys still single a candidate out, since an unfinished code answers with the codes
    // it can still become. Empty for a candidate that has no key of its own.
    std::vector<std::string> candidate_codes;
    // 候选词的英文释义,和候选同序等长,没有释义的那条为空。
    // Filled only while candidate glosses are enabled; a frontend that never asks for them pays
    // nothing, since the dictionary behind them is opened on first use.
    std::vector<std::string> candidate_glosses;
    // Set when the engine could answer the key but something behind it failed, such as a local input
    // mode whose table is missing or a word that could not be learned. Input stays usable, so a
    // frontend reports it rather than treating it as an error.
    std::optional<std::string> diagnostic;
};

class InputSessionAdapter
{
  public:
    InputSessionAdapter();
    // Prepared paths are captured for this adapter and retained across scheme/preferences changes.
    explicit InputSessionAdapter(const RuntimePaths &paths);
    ~InputSessionAdapter();

    InputSessionAdapter(const InputSessionAdapter &) = delete;
    InputSessionAdapter &operator=(const InputSessionAdapter &) = delete;

    InputSnapshot handle_character(char character);
    // Opens one of the engine's local input modes. The engine keys these off a capital delivered with
    // its shift_only flag, which no iOS key can produce, so the frontend names the mode instead and
    // this turns it back into the keystroke the engine expects. A mode that is switched off, or a
    // letter that names none, leaves the session untouched and reports itself unhandled.
    InputSnapshot open_local_mode(char trigger);
    // None while no local mode is open. A frontend needs this to know that its digits are input for a
    // Unicode code point rather than candidate numbers.
    bool in_unicode_mode() const;
    bool in_local_mode() const;
    InputSnapshot handle_candidate_key(char character);
    InputSnapshot handle_punctuation(char character);
    InputSnapshot handle_backspace();
    InputSnapshot commit_candidate();
    InputSnapshot finish_composition();
    InputSnapshot commit_raw();
    InputSnapshot cancel();
    InputSnapshot select_candidate(std::size_t index);
    // Returns false during composition; the platform retries after its current snapshot is idle.
    bool set_learning_enabled(bool enabled);
    bool learning_enabled() const;
    bool set_fuzzy_pinyin_rules(std::uint32_t rules);
    bool set_frequency_adjustment(FrequencyAdjustmentOptions options);
    FrequencyAdjustmentOptions frequency_adjustment() const;
    void set_wubi_mixed_pinyin(bool enabled);
    // Offers words from the packaged English dictionary alongside the Chinese candidates, so a latin
    // word can be committed without leaving the Chinese keyboard. The Engine applies this to Quanpin
    // and Shuangpin only, and only to an all-lowercase prefix. Returns false during composition,
    // like the other options the Engine reads from SessionOptions.
    bool set_english_mixed_candidates(bool enabled);
    bool english_mixed_candidates() const;
    void set_candidate_glosses_enabled(bool enabled);
    bool candidate_glosses_enabled() const;
    RuntimePaths runtime_paths() const;
    bool idle() const;
    PersonalDictionaryEditResult edit_personal_word(const std::optional<PersonalDictionaryEntry> &previous,
                                                    const std::optional<PersonalDictionaryEntry> &replacement,
                                                    const std::string &request_id);
    // The host supplies an Engine-staged, verified generation and owns all other
    // writers. Publish its durable pointer only after constructing the replacement
    // session. A throwing publisher leaves this adapter on its original paths.
    // Returns false during composition/local input, without invoking publish.
    bool activate_dictionary_generation(const RuntimePaths &paths, const std::function<void()> &publish);
    PersonalDictionaryPage personal_words(std::size_t offset, std::size_t limit) const;
    InputSnapshot edit_candidate(std::size_t index, const std::string &expected_word, CandidateAction action);
    InputSnapshot switch_to_shuangpin(bool uses_shuangpin);
    bool uses_shuangpin() const;
    InputSnapshot switch_to_shuangpin_profile(const std::string &name);
    std::string shuangpin_profile_name() const;
    InputSnapshot switch_to_wubi();
    InputSnapshot switch_to_japanese();
    InputSnapshot switch_to_nine_key();
    InputSnapshot choose_nine_key_spelling(std::size_t index);
    std::vector<std::string> nine_key_spellings() const;

  private:
    class Impl;
    void replace_session(SchemeType scheme, std::string profile, bool nine_key);
    bool learning_enabled_ = false;
    std::uint32_t fuzzy_pinyin_rules_ = 0;
    FrequencyAdjustmentOptions frequency_{FrequencyAdjustmentMode::Promote, 1, 1};
    bool wubi_mixed_pinyin_ = false;
    bool english_mixed_candidates_ = false;
    bool candidate_glosses_enabled_ = false;
    std::unique_ptr<EnglishDictionary> gloss_dictionary_;
    EnglishDictionary *gloss_dictionary();
    InputSnapshot make_snapshot(KeyResult result);
    std::unique_ptr<Impl> impl_;
};
} // namespace metasequoia::apple

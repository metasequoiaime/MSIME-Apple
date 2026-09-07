#pragma once

#include <cstddef>
#include <memory>
#include <optional>
#include <string>
#include <vector>

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
    std::unique_ptr<Impl> impl_;
    bool learning_enabled_ = false;
};
} // namespace metasequoia::apple

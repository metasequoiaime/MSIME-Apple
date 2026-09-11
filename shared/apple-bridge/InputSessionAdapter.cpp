#include "InputSessionAdapter.h"

#include <metasequoia/session.h>
#include "quanpin/quanpin_utils.h"

#include <utility>

namespace metasequoia::apple
{
class InputSessionAdapter::Impl
{
  public:
    explicit Impl(const RuntimePaths &runtime_paths, SchemeType scheme = SchemeType::Quanpin,
                  std::string profile = "xiaohe", bool learning = false, std::uint32_t fuzzy = 0,
                  FrequencyAdjustmentOptions frequency = {FrequencyAdjustmentMode::Promote, 1, 1},
                  bool english_mixed = false)
        : paths{runtime_paths}, session{MakeOptions(paths, scheme, profile, learning, fuzzy, frequency, english_mixed)},
          profile_name{std::move(profile)}
    {
    }

    static SessionOptions MakeOptions(const RuntimePaths &paths, SchemeType scheme, const std::string &profile,
                                      bool learning, std::uint32_t fuzzy, FrequencyAdjustmentOptions frequency,
                                      bool english_mixed)
    {
        SessionOptions session_options;
        session_options.paths = paths;
        session_options.scheme = scheme;
        session_options.shuangpin_profile = GetShuangpinProfile(profile);
        // This used to ride on SessionOptions::autocorrect, which defaulted to true. The Engine
        // replaced it with a per-type mask that defaults to 0, so leaving it unset would quietly
        // switch quanpin autocorrection off for every iOS user who has it today. State the types
        // the old flag covered instead.
        session_options.autocorrect_types = quanpin::kAutocorrectTransposition | quanpin::kAutocorrectNeighbor;
        session_options.learning = learning;
        session_options.fuzzy_pinyin.rules = fuzzy;
        session_options.frequency = learning ? frequency : FrequencyAdjustmentOptions{};
        // Mixes English words into the Chinese candidates. The Engine keeps its own guards: Quanpin
        // and Shuangpin only, an all-lowercase prefix, and at least english.minimum_prefix letters.
        session_options.english.mixed_candidates = english_mixed;
        // The iOS product ships the locked main, English and expressive databases.
        LocalModeOptions options;
        options.unicode = true;
        options.date_time = true;
        options.quick_phrase = true;
        options.super_jianpin = true;
        options.emoji = true;
        options.kaomoji = true;
        options.temporary_english = true;
        options.temporary_japanese = true;
        session_options.local_modes = options;
        return session_options;
    }

    RuntimePaths paths;
    Session session;
    std::string profile_name;
    bool nine_key = false;
};

namespace
{
InputSnapshot MakeSnapshot(const Session &session, KeyResult result)
{
    InputSnapshot snapshot;
    snapshot.handled = result.handled;
    snapshot.commit = std::move(result.commit);
    snapshot.diagnostic = std::move(result.diagnostic);
    const auto view = session.snapshot();
    snapshot.preedit = view.preedit;
    snapshot.candidates.reserve(view.candidates.size());
    snapshot.candidate_codes.reserve(view.candidates.size());
    for (const auto &candidate : view.candidates)
    {
        snapshot.candidates.push_back(candidate.word);
        snapshot.candidate_codes.push_back(candidate.pinyin);
    }
    return snapshot;
}
} // namespace

InputSessionAdapter::InputSessionAdapter() : InputSessionAdapter(RuntimePaths::legacy())
{
}

InputSessionAdapter::InputSessionAdapter(const RuntimePaths &paths)
    : impl_(std::make_unique<Impl>(paths, SchemeType::Quanpin, "xiaohe", learning_enabled_, fuzzy_pinyin_rules_,
                                   frequency_, english_mixed_candidates_))
{
}

void InputSessionAdapter::replace_session(SchemeType scheme, std::string profile, bool nine_key)
{
    impl_ = std::make_unique<Impl>(impl_->paths, scheme, std::move(profile), learning_enabled_, fuzzy_pinyin_rules_,
                                   frequency_, english_mixed_candidates_);
    impl_->nine_key = nine_key;
    impl_->session.set_nine_key_enabled(nine_key);
    impl_->session.set_wubi_mixed_pinyin(wubi_mixed_pinyin_);
}

InputSessionAdapter::~InputSessionAdapter() = default;

InputSnapshot InputSessionAdapter::handle_character(char character)
{
    // A-Z during a composition is helpcode, which the engine narrows down candidates with. Outside
    // one it is a capital the user is typing, and the keyboard hands those to the client itself, so
    // it stays unhandled here. The engine applies its own rules to the helpcode -- Quanpin and
    // Shuangpin only, and only while the scheme has it switched on.
    if (character >= 'A' && character <= 'Z' && impl_->session.snapshot().preedit.empty())
    {
        return MakeSnapshot(impl_->session, KeyResult{});
    }
    return MakeSnapshot(impl_->session, impl_->session.character(character));
}

InputSnapshot InputSessionAdapter::open_local_mode(char trigger)
{
    // The engine guards every trigger on there being no composition, so a mode opened on top of one
    // would be a mode the user did not ask for. handle_character rejects A-Z outright, which is right
    // for a keystroke and wrong here, so the session is called directly with the shift_only flag the
    // triggers are keyed off.
    if (trigger < 'A' || trigger > 'Z' || !impl_->session.snapshot().preedit.empty())
    {
        return MakeSnapshot(impl_->session, KeyResult{});
    }
    return MakeSnapshot(impl_->session, impl_->session.character(trigger, true));
}

bool InputSessionAdapter::in_local_mode() const
{
    return impl_->session.snapshot().local_mode != LocalInputMode::None;
}

bool InputSessionAdapter::in_unicode_mode() const
{
    return impl_->session.snapshot().local_mode == LocalInputMode::Unicode;
}

InputSnapshot InputSessionAdapter::handle_candidate_key(char character)
{
    return MakeSnapshot(impl_->session, impl_->session.candidate_key(character));
}

InputSnapshot InputSessionAdapter::handle_punctuation(char character)
{
    return MakeSnapshot(impl_->session, impl_->session.punctuation(character));
}

InputSnapshot InputSessionAdapter::handle_backspace()
{
    return MakeSnapshot(impl_->session, impl_->session.command(Command::Backspace));
}

InputSnapshot InputSessionAdapter::commit_candidate()
{
    return MakeSnapshot(impl_->session, impl_->session.command(Command::CommitCandidate));
}

InputSnapshot InputSessionAdapter::finish_composition()
{
    return MakeSnapshot(impl_->session, impl_->session.finish());
}

InputSnapshot InputSessionAdapter::commit_raw()
{
    return MakeSnapshot(impl_->session, impl_->session.command(Command::CommitRaw));
}

InputSnapshot InputSessionAdapter::cancel()
{
    return MakeSnapshot(impl_->session, impl_->session.command(Command::Cancel));
}

InputSnapshot InputSessionAdapter::select_candidate(std::size_t index)
{
    return MakeSnapshot(impl_->session, impl_->session.select(index));
}

bool InputSessionAdapter::set_learning_enabled(bool enabled)
{
    if (enabled == learning_enabled_)
        return true;
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return false;
    learning_enabled_ = enabled;
    replace_session(current.scheme, impl_->profile_name, impl_->nine_key);
    return true;
}

void InputSessionAdapter::set_wubi_mixed_pinyin(bool enabled)
{
    if (enabled == wubi_mixed_pinyin_)
        return;
    wubi_mixed_pinyin_ = enabled;
    impl_->session.set_wubi_mixed_pinyin(enabled);
}

bool InputSessionAdapter::set_english_mixed_candidates(bool enabled)
{
    if (enabled == english_mixed_candidates_)
        return true;
    // The Engine takes this through SessionOptions, so the session is rebuilt rather than retuned.
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return false;
    english_mixed_candidates_ = enabled;
    replace_session(current.scheme, impl_->profile_name, impl_->nine_key);
    return true;
}

bool InputSessionAdapter::english_mixed_candidates() const
{
    return english_mixed_candidates_;
}

bool InputSessionAdapter::set_fuzzy_pinyin_rules(std::uint32_t rules)
{
    rules &= 0x7ff;
    if (rules == fuzzy_pinyin_rules_)
        return true;
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return false;
    fuzzy_pinyin_rules_ = rules;
    replace_session(current.scheme, impl_->profile_name, impl_->nine_key);
    return true;
}

bool InputSessionAdapter::learning_enabled() const
{
    return learning_enabled_;
}

bool InputSessionAdapter::idle() const
{
    const auto snapshot = impl_->session.snapshot();
    return snapshot.preedit.empty() && snapshot.local_mode == LocalInputMode::None;
}

RuntimePaths InputSessionAdapter::runtime_paths() const
{
    return impl_->paths;
}

bool InputSessionAdapter::set_frequency_adjustment(FrequencyAdjustmentOptions options)
{
    switch (options.mode)
    {
    case FrequencyAdjustmentMode::Disabled:
    case FrequencyAdjustmentMode::Pin:
    case FrequencyAdjustmentMode::Halve:
    case FrequencyAdjustmentMode::Linear:
    case FrequencyAdjustmentMode::Promote:
        break;
    default:
        return false;
    }
    if (options.trigger_count < 1 || options.trigger_count > 10 || options.linear_step < 1 || options.linear_step > 10)
        return false;
    if (options.mode == frequency_.mode && options.trigger_count == frequency_.trigger_count &&
        options.linear_step == frequency_.linear_step)
        return true;
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return false;
    frequency_ = options;
    if (!learning_enabled_)
        return true;
    replace_session(current.scheme, impl_->profile_name, impl_->nine_key);
    return true;
}

FrequencyAdjustmentOptions InputSessionAdapter::frequency_adjustment() const
{
    return frequency_;
}

PersonalDictionaryEditResult InputSessionAdapter::edit_personal_word(
    const std::optional<PersonalDictionaryEntry> &previous, const std::optional<PersonalDictionaryEntry> &replacement,
    const std::string &request_id)
{
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return {false, "Composition is active"};
    const auto paths = impl_->paths;
    const auto profile = impl_->profile_name;
    const bool nine_key = impl_->nine_key;
    impl_.reset();
    const auto result = edit_personal_dictionary(paths, previous, replacement, request_id);
    impl_ = std::make_unique<Impl>(paths, current.scheme, profile, learning_enabled_, fuzzy_pinyin_rules_, frequency_);
    impl_->nine_key = nine_key;
    impl_->session.set_nine_key_enabled(nine_key);
    impl_->session.set_wubi_mixed_pinyin(wubi_mixed_pinyin_);
    return result;
}

bool InputSessionAdapter::activate_dictionary_generation(const RuntimePaths &paths,
                                                         const std::function<void()> &publish)
{
    const auto current = impl_->session.snapshot();
    if (!current.preedit.empty() || current.local_mode != LocalInputMode::None)
        return false;
    paths.validate();
    auto replacement = std::make_unique<Impl>(paths, current.scheme, impl_->profile_name, learning_enabled_,
                                              fuzzy_pinyin_rules_, frequency_);
    replacement->nine_key = impl_->nine_key;
    replacement->session.set_nine_key_enabled(replacement->nine_key);
    replacement->session.set_wubi_mixed_pinyin(wubi_mixed_pinyin_);
    // No throwing operation follows publication: swap only transfers ownership.
    // Constructing beforehand also keeps the original session intact on failure.
    publish();
    impl_.swap(replacement);
    return true;
}

PersonalDictionaryPage InputSessionAdapter::personal_words(std::size_t offset, std::size_t limit) const
{
    return personal_dictionary_entries(impl_->paths, offset, limit);
}

InputSnapshot InputSessionAdapter::edit_candidate(std::size_t index, const std::string &expected_word,
                                                  CandidateAction action)
{
    const auto current = impl_->session.snapshot();
    if (index >= current.candidates.size() || current.candidates[index].word != expected_word)
        return MakeSnapshot(impl_->session, KeyResult{});
    KeyResult result;
    switch (action)
    {
    case CandidateAction::Promote:
        result = impl_->session.pin(index);
        break;
    case CandidateAction::Remove:
        result = impl_->session.remove(index);
        break;
    case CandidateAction::FixFirst:
        result = impl_->session.fix_position(index, 1);
        break;
    case CandidateAction::ClearPosition:
        result = impl_->session.clear_position(index);
        break;
    }
    return MakeSnapshot(impl_->session, std::move(result));
}

InputSnapshot InputSessionAdapter::switch_to_shuangpin(bool uses_shuangpin)
{
    if (impl_->session.snapshot().scheme == (uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin) &&
        !impl_->nine_key && (!uses_shuangpin || impl_->profile_name == "xiaohe"))
    {
        return MakeSnapshot(impl_->session, {});
    }
    const auto result = impl_->session.finish();
    auto snapshot = MakeSnapshot(impl_->session, result);
    const auto scheme = uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin;
    replace_session(scheme, "xiaohe", false);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_shuangpin_profile(const std::string &name)
{
    if (name != "xiaohe" && name != "ziranma" && name != "shoudao" && name != "microsoft")
        return MakeSnapshot(impl_->session, {});
    if (uses_shuangpin() && !impl_->nine_key && impl_->profile_name == name)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    replace_session(SchemeType::Shuangpin, name, false);
    return snapshot;
}
std::string InputSessionAdapter::shuangpin_profile_name() const
{
    return impl_->profile_name;
}

InputSnapshot InputSessionAdapter::switch_to_wubi()
{
    if (impl_->session.snapshot().scheme == SchemeType::Wubi && !impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    replace_session(SchemeType::Wubi, "xiaohe", false);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_japanese()
{
    if (impl_->session.snapshot().scheme == SchemeType::JapaneseRomaji && !impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    replace_session(SchemeType::JapaneseRomaji, "xiaohe", false);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_nine_key()
{
    if (impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    replace_session(SchemeType::Quanpin, "xiaohe", true);
    return snapshot;
}
InputSnapshot InputSessionAdapter::choose_nine_key_spelling(std::size_t index)
{
    return MakeSnapshot(impl_->session, impl_->session.choose_nine_key_spelling(index));
}
std::vector<std::string> InputSessionAdapter::nine_key_spellings() const
{
    return impl_->session.snapshot().nine_key_spellings;
}

bool InputSessionAdapter::uses_shuangpin() const
{
    return impl_->session.snapshot().scheme == SchemeType::Shuangpin;
}
} // namespace metasequoia::apple

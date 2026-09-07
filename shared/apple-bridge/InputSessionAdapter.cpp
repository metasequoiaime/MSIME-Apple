#include "InputSessionAdapter.h"

#include <metasequoia/session.h>

#include <utility>

namespace metasequoia::apple
{
class InputSessionAdapter::Impl
{
  public:
    explicit Impl(SchemeType scheme = SchemeType::Quanpin, std::string profile = "xiaohe")
        : session{MakeOptions(scheme, profile)}, profile_name{std::move(profile)}
    {
    }

    static SessionOptions MakeOptions(SchemeType scheme, const std::string &profile)
    {
        SessionOptions session_options;
        // The iOS installer still supplies the existing writable dictionary layout. Capture it
        // once per session; moving installation to separate resource generations is independent
        // of routing editing actions through the public facade.
        session_options.paths = RuntimePaths::legacy();
        session_options.scheme = scheme;
        session_options.shuangpin_profile = GetShuangpinProfile(profile);
        session_options.learning = false;
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
    for (const auto &candidate : view.candidates)
    {
        snapshot.candidates.push_back(candidate.word);
    }
    return snapshot;
}
} // namespace

InputSessionAdapter::InputSessionAdapter() : impl_(std::make_unique<Impl>())
{
}

InputSessionAdapter::~InputSessionAdapter() = default;

InputSnapshot InputSessionAdapter::handle_character(char character)
{
    // The engine accepts A-Z during a composition as helpcode input, which this keyboard does not offer.
    // Reject it here so an uppercase letter stays unhandled and the frontend passes it to the client,
    // preserving the keyboard's existing uppercase passthrough behavior.
    if (character >= 'A' && character <= 'Z')
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

InputSnapshot InputSessionAdapter::switch_to_shuangpin(bool uses_shuangpin)
{
    if (impl_->session.snapshot().scheme == (uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin) && !impl_->nine_key && (!uses_shuangpin || impl_->profile_name == "xiaohe"))
    {
        return MakeSnapshot(impl_->session, {});
    }
    const auto result = impl_->session.finish();
    auto snapshot = MakeSnapshot(impl_->session, result);
    const auto scheme = uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin;
    impl_ = std::make_unique<Impl>(scheme);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_shuangpin_profile(const std::string &name)
{
    if (name != "xiaohe" && name != "ziranma" && name != "shoudao" && name != "microsoft")
        return MakeSnapshot(impl_->session, {});
    if (uses_shuangpin() && !impl_->nine_key && impl_->profile_name == name)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    impl_ = std::make_unique<Impl>(SchemeType::Shuangpin, name);
    return snapshot;
}
std::string InputSessionAdapter::shuangpin_profile_name() const { return impl_->profile_name; }

InputSnapshot InputSessionAdapter::switch_to_wubi()
{
    if (impl_->session.snapshot().scheme == SchemeType::Wubi && !impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    impl_ = std::make_unique<Impl>(SchemeType::Wubi);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_japanese()
{
    if (impl_->session.snapshot().scheme == SchemeType::JapaneseRomaji && !impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    impl_ = std::make_unique<Impl>(SchemeType::JapaneseRomaji);
    return snapshot;
}

InputSnapshot InputSessionAdapter::switch_to_nine_key()
{
    if (impl_->nine_key)
        return MakeSnapshot(impl_->session, {});
    auto snapshot = MakeSnapshot(impl_->session, impl_->session.finish());
    impl_ = std::make_unique<Impl>();
    impl_->session.set_nine_key_enabled(true);
    impl_->nine_key = true;
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

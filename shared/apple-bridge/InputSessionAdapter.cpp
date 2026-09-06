#include "InputSessionAdapter.h"

#include "core/input_session.h"

#include <utility>

namespace metasequoia::apple {
class InputSessionAdapter::Impl {
public:
  explicit Impl(SchemeType scheme = SchemeType::Quanpin)
      : session{scheme, true, true, true, false} {
    // Only the modes this frontend can answer are offered, and that is decided by the dictionary
    // product it ships. Engine's mobile dictionary profile is compact pinyin — its manifest declares
    // features ['pinyin'] — so quick phrases have no quick_parases table here, and temporary
    // Japanese no dict_japanese.dat; emoji and kaomoji read others.db and temporary English reads
    // english.db, neither of which is fetched on Apple at all. What is left needs nothing beyond
    // the pinyin tables: Unicode parses its own input, date and time has a built-in provider, and
    // super jianpin queries the pinyin tables directly.
    LocalModeOptions options;
    options.unicode = true;
    options.date_time = true;
    options.quick_phrase = false;
    options.super_jianpin = true;
    options.emoji = false;
    options.kaomoji = false;
    options.temporary_english = false;
    options.temporary_japanese = false;
    session.set_local_mode_options(options);
  }

  InputSession session;
};

namespace {
InputSnapshot MakeSnapshot(const InputSession &session, KeyResult result) {
  InputSnapshot snapshot;
  snapshot.handled = result.handled;
  snapshot.commit = std::move(result.commit);
  snapshot.diagnostic = std::move(result.diagnostic);
  snapshot.preedit = session.preedit();
  snapshot.candidates.reserve(session.candidates().size());
  for (const auto &candidate : session.candidates()) {
    snapshot.candidates.push_back(candidate.word);
  }
  return snapshot;
}
} // namespace

InputSessionAdapter::InputSessionAdapter() : impl_(std::make_unique<Impl>()) {}

InputSessionAdapter::~InputSessionAdapter() = default;

InputSnapshot InputSessionAdapter::handle_character(char character) {
  // The engine accepts A-Z during a composition as helpcode input, which no Apple frontend offers.
  // Reject it here so an uppercase letter stays unhandled and the frontend passes it to the client,
  // matching what core/input_session.h still documents and what the macOS controller does.
  if (character >= 'A' && character <= 'Z') {
    return MakeSnapshot(impl_->session, KeyResult{});
  }
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_character(character));
}

InputSnapshot InputSessionAdapter::open_local_mode(char trigger) {
  // The engine guards every trigger on there being no composition, so a mode opened on top of one
  // would be a mode the user did not ask for. handle_character rejects A-Z outright, which is right
  // for a keystroke and wrong here, so the session is called directly with the shift_only flag the
  // triggers are keyed off.
  if (trigger < 'A' || trigger > 'Z' || impl_->session.has_composition()) {
    return MakeSnapshot(impl_->session, KeyResult{});
  }
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_character(trigger, true));
}

bool InputSessionAdapter::in_unicode_mode() const {
  return impl_->session.local_input_mode() == LocalInputMode::Unicode;
}

InputSnapshot InputSessionAdapter::handle_candidate_key(char character) {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_candidate_key(character));
}

InputSnapshot InputSessionAdapter::handle_punctuation(char character) {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_punctuation(character));
}

InputSnapshot InputSessionAdapter::handle_backspace() {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_command(Command::Backspace));
}

InputSnapshot InputSessionAdapter::commit_candidate() {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_command(Command::CommitCandidate));
}

InputSnapshot InputSessionAdapter::finish_composition() {
  return MakeSnapshot(impl_->session, impl_->session.finish_composition());
}

InputSnapshot InputSessionAdapter::commit_raw() {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_command(Command::CommitRaw));
}

InputSnapshot InputSessionAdapter::cancel() {
  return MakeSnapshot(impl_->session,
                      impl_->session.handle_command(Command::Cancel));
}

InputSnapshot InputSessionAdapter::select_candidate(std::size_t index) {
  return MakeSnapshot(impl_->session, impl_->session.select_candidate(index));
}

InputSnapshot InputSessionAdapter::switch_to_shuangpin(bool uses_shuangpin) {
  if (uses_shuangpin == this->uses_shuangpin()) {
    return MakeSnapshot(impl_->session, {});
  }
  const auto result = impl_->session.finish_composition();
  auto snapshot = MakeSnapshot(impl_->session, result);
  const auto scheme =
      uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin;
  impl_ = std::make_unique<Impl>(scheme);
  return snapshot;
}

bool InputSessionAdapter::uses_shuangpin() const {
  return impl_->session.scheme_type() == SchemeType::Shuangpin;
}
} // namespace metasequoia::apple

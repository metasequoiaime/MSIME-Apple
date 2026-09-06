#include "InputSessionAdapter.h"

#include <metasequoia/session.h>

#include <utility>

namespace metasequoia::apple {
class InputSessionAdapter::Impl {
public:
  explicit Impl(SchemeType scheme = SchemeType::Quanpin)
      : session{MakeOptions(scheme)} {}

  static SessionOptions MakeOptions(SchemeType scheme) {
    SessionOptions session_options;
    // The iOS installer still supplies the existing writable dictionary layout. Capture it
    // once per session; moving installation to separate resource generations is independent
    // of routing editing actions through the public facade.
    session_options.paths = RuntimePaths::legacy();
    session_options.scheme = scheme;
    session_options.learning = false;
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
    session_options.local_modes = options;
    return session_options;
  }

  Session session;
};

namespace {
InputSnapshot MakeSnapshot(const Session &session, KeyResult result) {
  InputSnapshot snapshot;
  snapshot.handled = result.handled;
  snapshot.commit = std::move(result.commit);
  snapshot.diagnostic = std::move(result.diagnostic);
  const auto view = session.snapshot();
  snapshot.preedit = view.preedit;
  snapshot.candidates.reserve(view.candidates.size());
  for (const auto &candidate : view.candidates) {
    snapshot.candidates.push_back(candidate.word);
  }
  return snapshot;
}
} // namespace

InputSessionAdapter::InputSessionAdapter() : impl_(std::make_unique<Impl>()) {}

InputSessionAdapter::~InputSessionAdapter() = default;

InputSnapshot InputSessionAdapter::handle_character(char character) {
  // The engine accepts A-Z during a composition as helpcode input, which this keyboard does not offer.
  // Reject it here so an uppercase letter stays unhandled and the frontend passes it to the client,
  // preserving the keyboard's existing uppercase passthrough behavior.
  if (character >= 'A' && character <= 'Z') {
    return MakeSnapshot(impl_->session, KeyResult{});
  }
  return MakeSnapshot(impl_->session,
                      impl_->session.character(character));
}

InputSnapshot InputSessionAdapter::open_local_mode(char trigger) {
  // The engine guards every trigger on there being no composition, so a mode opened on top of one
  // would be a mode the user did not ask for. handle_character rejects A-Z outright, which is right
  // for a keystroke and wrong here, so the session is called directly with the shift_only flag the
  // triggers are keyed off.
  if (trigger < 'A' || trigger > 'Z' || !impl_->session.snapshot().preedit.empty()) {
    return MakeSnapshot(impl_->session, KeyResult{});
  }
  return MakeSnapshot(impl_->session,
                      impl_->session.character(trigger, true));
}

bool InputSessionAdapter::in_unicode_mode() const {
  return impl_->session.snapshot().local_mode == LocalInputMode::Unicode;
}

InputSnapshot InputSessionAdapter::handle_candidate_key(char character) {
  return MakeSnapshot(impl_->session,
                      impl_->session.candidate_key(character));
}

InputSnapshot InputSessionAdapter::handle_punctuation(char character) {
  return MakeSnapshot(impl_->session,
                      impl_->session.punctuation(character));
}

InputSnapshot InputSessionAdapter::handle_backspace() {
  return MakeSnapshot(impl_->session,
                      impl_->session.command(Command::Backspace));
}

InputSnapshot InputSessionAdapter::commit_candidate() {
  return MakeSnapshot(impl_->session,
                      impl_->session.command(Command::CommitCandidate));
}

InputSnapshot InputSessionAdapter::finish_composition() {
  return MakeSnapshot(impl_->session, impl_->session.finish());
}

InputSnapshot InputSessionAdapter::commit_raw() {
  return MakeSnapshot(impl_->session,
                      impl_->session.command(Command::CommitRaw));
}

InputSnapshot InputSessionAdapter::cancel() {
  return MakeSnapshot(impl_->session,
                      impl_->session.command(Command::Cancel));
}

InputSnapshot InputSessionAdapter::select_candidate(std::size_t index) {
  return MakeSnapshot(impl_->session, impl_->session.select(index));
}

InputSnapshot InputSessionAdapter::switch_to_shuangpin(bool uses_shuangpin) {
  if (uses_shuangpin == this->uses_shuangpin()) {
    return MakeSnapshot(impl_->session, {});
  }
  const auto result = impl_->session.finish();
  auto snapshot = MakeSnapshot(impl_->session, result);
  const auto scheme =
      uses_shuangpin ? SchemeType::Shuangpin : SchemeType::Quanpin;
  impl_ = std::make_unique<Impl>(scheme);
  return snapshot;
}

bool InputSessionAdapter::uses_shuangpin() const {
  return impl_->session.snapshot().scheme == SchemeType::Shuangpin;
}
} // namespace metasequoia::apple

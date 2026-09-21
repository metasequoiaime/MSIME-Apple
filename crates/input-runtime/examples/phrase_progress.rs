//! What the user sees while a phrase is being put together out of two selections.
//!
//! Picking a candidate that consumes only part of the input leaves the Engine composing: it keeps
//! the piece that was chosen, offers candidates for the rest, and stores the whole phrase once the
//! input runs out. `engine-bridge/examples/phrase_creation_dictionary.rs` pins the storing half.
//! This one pins the half the user actually looks at - what the host is told to put on screen and
//! what it is told to send to the document in between - because that is where the reference and
//! this client could differ without either of them being wrong about the dictionary.
//!
//! The reference keeps the chosen word inside its composition (`word_for_creating_word` is
//! prepended to the reading, and the caret is shifted past it) and commits the phrase as one piece
//! at the end. This client now does the same for hosts that ask for it, and the difference is not
//! observable without real dictionaries: an empty one has no partial candidate to pick.
//!
//! usage: phrase_progress <verified-dictionary-directory>

use msime_engine_bridge::{prepare_options, Command, Session};
use msime_input_runtime::{Action, Runtime};

/// Pinyin for a phrase whose leading part is a word of its own, so the first candidate list holds
/// something that consumes only part of the input.
const KEYS: &str = "haitanpaobu";
const LEADING: &str = "海滩";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: phrase_progress <verified-dictionary-directory>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "phrase-progress-probe",
    )?;
    options.learning = true;

    let compose = |runtime: &mut Runtime<Session>| -> Result<(), Box<dyn std::error::Error>> {
        for byte in KEYS.bytes() {
            runtime.dispatch(Action::Character {
                value: byte,
                shift: false,
            })?;
        }
        Ok(())
    };
    let leading = |runtime: &Runtime<Session>| -> Result<msime_input_runtime::CandidateId, Box<dyn std::error::Error>> {
        let view = runtime.view();
        let index = view
            .candidates
            .iter()
            .position(|candidate| candidate.text == LEADING)
            .ok_or("no partial candidate for the leading word")?;
        Ok(view.candidates[index].id)
    };

    // A host that does not draw the field is left exactly as it was: the piece goes to the document
    // the moment it is picked.
    let mut plain = Runtime::new(Session::new(&options)?, 9)?;
    plain.focus(true)?;
    compose(&mut plain)?;
    let id = leading(&plain)?;
    let picked = plain.dispatch(Action::Select(id))?;
    assert_eq!(picked.commit.as_deref(), Some(LEADING), "unheld commit");
    assert!(picked.view.phrase_prefix.is_empty());
    assert!(
        !picked.view.editing_text.is_empty(),
        "the rest is still composing"
    );

    // A host that draws it sees the piece in the view and nothing in the document until the phrase
    // is finished, and then the whole phrase at once.
    let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
    runtime.set_phrase_preedit(true);
    runtime.focus(true)?;
    compose(&mut runtime)?;
    let id = leading(&runtime)?;
    let held = runtime.dispatch(Action::Select(id))?;
    assert_eq!(
        held.commit, None,
        "the piece must not reach the document yet"
    );
    assert_eq!(held.view.phrase_prefix, LEADING);
    let remaining = held.view.editing_text.clone();
    assert!(!remaining.is_empty(), "the rest is still composing");

    let rest = held.view.candidates[0].id;
    let done = runtime.dispatch(Action::Select(rest))?;
    let committed = done.commit.ok_or("the phrase never reached the document")?;
    assert!(
        committed.starts_with(LEADING) && committed.chars().count() > LEADING.chars().count(),
        "the phrase committed as {committed:?}, without both pieces"
    );
    assert!(done.view.phrase_prefix.is_empty());
    assert!(done.view.editing_text.is_empty());

    // Escape throws away the piece with the rest of the composition.
    compose(&mut runtime)?;
    let id = leading(&runtime)?;
    runtime.dispatch(Action::Select(id))?;
    let cancelled = runtime.dispatch(Action::Command(Command::Cancel))?;
    assert_eq!(cancelled.commit, None, "escape must not commit the piece");
    assert!(cancelled.view.phrase_prefix.is_empty());

    // Deleting the remaining reading commits the piece rather than losing it.
    compose(&mut runtime)?;
    let id = leading(&runtime)?;
    let held = runtime.dispatch(Action::Select(id))?;
    let mut transition = held;
    while !transition.view.editing_text.is_empty() {
        transition = runtime.dispatch(Action::Command(Command::Backspace))?;
    }
    assert_eq!(transition.commit.as_deref(), Some(LEADING));
    assert!(transition.view.phrase_prefix.is_empty());

    println!(
        "phrase progress: {LEADING} held while {remaining:?} was composed, committed as {committed}"
    );
    Ok(())
}

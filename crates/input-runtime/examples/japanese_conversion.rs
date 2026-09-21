//! What a Japanese composition does when the user presses Space and Enter, against the real Engine.
//!
//! Romaji is not what the user typed; かな is. The Engine keeps both - `editing_text` is the romaji
//! and `reading` the kana - and has one command for each ending: `CommitRaw` gives the romaji back,
//! `CommitReading` gives the kana. Every desktop host sent `CommitRaw` on Enter for every scheme,
//! so Japanese input committed `nihon` where the user meant にほん. This pins what each command
//! actually produces, so a host reading this file knows which one its Enter key has to send.
//!
//! usage: japanese_conversion <verified-dictionary-directory>

use msime_engine_bridge::{prepare_options, Command, Session};
use msime_input_runtime::{Action, Runtime};

const KEYS: &str = "nihon";

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: japanese_conversion <verified-dictionary-directory>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "japanese-conversion-probe",
    )?;
    options.scheme = 3;

    let compose = |runtime: &mut Runtime<Session>| -> Result<(), Box<dyn std::error::Error>> {
        for byte in KEYS.bytes() {
            runtime.dispatch(Action::Character {
                value: byte,
                shift: false,
            })?;
        }
        Ok(())
    };

    // What is on screen: the romaji as the editing text, the kana as the reading.
    let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
    runtime.focus(true)?;
    compose(&mut runtime)?;
    let view = runtime.view();
    assert_eq!(view.editing_text, KEYS);
    let reading = view.reading.clone();
    assert!(
        !reading.is_empty() && !reading.is_ascii(),
        "the reading is the kana, not the romaji: {reading:?}"
    );
    let candidates = view.candidates.len();
    assert!(candidates > 1, "conversion needs something to step through");

    // Enter with no conversion started: the kana, which is what the user typed.
    let committed = runtime
        .dispatch(Action::Command(Command::CommitReading))?
        .commit
        .ok_or("CommitReading committed nothing")?;
    assert_eq!(committed, reading, "Enter must give the kana back");

    // And the command the hosts used to send instead, so the difference is on the record.
    let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
    runtime.focus(true)?;
    compose(&mut runtime)?;
    let raw = runtime
        .dispatch(Action::Command(Command::CommitRaw))?
        .commit
        .ok_or("CommitRaw committed nothing")?;
    assert_eq!(
        raw, KEYS,
        "CommitRaw is the romaji, which is why Enter cannot send it"
    );

    // Space steps through the conversions, and Enter takes the one the user stopped on.
    let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
    runtime.focus(true)?;
    compose(&mut runtime)?;
    let first = runtime.view().candidates[0].text.clone();
    runtime.dispatch(Action::NextCandidate)?;
    let second = runtime.view().candidates[1].text.clone();
    let id = runtime.view().candidates[1].id;
    let chosen = runtime
        .dispatch(Action::Select(id))?
        .commit
        .ok_or("selecting a candidate committed nothing")?;
    assert_eq!(chosen, second);
    assert_ne!(first, second, "stepping has to reach a different word");

    println!(
        "japanese conversion: {KEYS:?} reads as {reading}, Enter alone commits it, CommitRaw would commit {raw:?}, and stepping once commits {chosen}"
    );
    Ok(())
}

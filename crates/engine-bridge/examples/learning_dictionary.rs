//! Check candidate learning against the pinned production dictionaries.
//!
//! Learning is a ranking change, so it can only be observed where a ranking exists: with the
//! synthetic dictionary the unit tests build, a query returns too few entries for "moved up" to
//! mean anything. This probe therefore takes a resource directory staged from
//! `resources/desktop-dictionary.lock.json`, and covers the three halves of the setting - that a
//! selection is remembered across sessions, that turning learning off stops it being written, and
//! that resetting learned data puts the packaged order back.
use msime_engine_bridge::{prepare_options, reset_learned_data, EngineOptions, Session};

const KEYS: &[u8] = b"nihao";
/// Deep enough that promotion is visible, shallow enough to stay on the first page.
const SELECTED: usize = 3;

struct Store {
    resources: std::path::PathBuf,
    _temporary: tempfile::TempDir,
    user: std::path::PathBuf,
    cache: std::path::PathBuf,
}

impl Store {
    fn new(resources: &std::path::Path) -> Result<Self, Box<dyn std::error::Error>> {
        let temporary = tempfile::tempdir()?;
        let user = temporary.path().join("user");
        let cache = temporary.path().join("cache");
        Ok(Self {
            resources: resources.to_path_buf(),
            _temporary: temporary,
            user,
            cache,
        })
    }

    fn options(&self, learning: bool) -> Result<EngineOptions, Box<dyn std::error::Error>> {
        let mut options = prepare_options(
            self.resources
                .to_str()
                .ok_or("resource path is not UTF-8")?,
            self.user.to_str().ok_or("user path is not UTF-8")?,
            self.cache.to_str().ok_or("cache path is not UTF-8")?,
            "learning-fixture",
        )?;
        options.learning = learning;
        Ok(options)
    }

    /// A fresh session every time: learning that only survives inside one session would not be
    /// learning, so the reading has to come from a session that was opened after the selection.
    fn candidates(&self, learning: bool) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(learning)?)?;
        for character in KEYS {
            session.character(*character, false)?;
        }
        Ok(session.snapshot()?.candidates)
    }

    fn select(&self, learning: bool, word: &str) -> Result<(), Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(learning)?)?;
        for character in KEYS {
            session.character(*character, false)?;
        }
        let candidates = session.snapshot()?.candidates;
        let index = candidates
            .iter()
            .position(|candidate| candidate == word)
            .ok_or_else(|| format!("{word} is no longer offered: {candidates:?}"))?;
        let committed = session.select(index)?;
        if !committed.has_commit || committed.commit != word {
            return Err(format!("selecting {word} committed {:?}", committed.commit).into());
        }
        Ok(())
    }
}

fn rank(candidates: &[String], word: &str) -> usize {
    candidates
        .iter()
        .position(|candidate| candidate == word)
        .unwrap_or(usize::MAX)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: learning_dictionary <verified-resources>")?,
    )?;

    // Learning on: the selection outranks where it started, and the new order survives the session
    // it was made in.
    let remembering = Store::new(&resources)?;
    let packaged = remembering.candidates(true)?;
    let chosen = packaged
        .get(SELECTED)
        .ok_or("the dictionary offered too few candidates")?
        .clone();
    remembering.select(true, &chosen)?;
    let learned = remembering.candidates(true)?;
    let promoted = rank(&learned, &chosen);
    assert!(
        promoted < SELECTED,
        "{chosen} stayed at {promoted}: {learned:?}"
    );

    // Reset puts the packaged order back. This runs on the store that has something to clear, so a
    // reset that silently did nothing would leave the promotion in place and fail here.
    reset_learned_data(&remembering.options(true)?)?;
    assert_eq!(
        remembering.candidates(true)?,
        packaged,
        "reset did not restore the packaged order"
    );

    // Learning off: the same selection on a clean store changes nothing. A separate store, because
    // the point is what was written, and the one above has been written to.
    let forgetting = Store::new(&resources)?;
    let before = forgetting.candidates(true)?;
    let ignored = before
        .get(SELECTED)
        .ok_or("the dictionary offered too few candidates")?
        .clone();
    forgetting.select(false, &ignored)?;
    assert_eq!(
        forgetting.candidates(true)?,
        before,
        "learning was written while turned off"
    );

    println!("candidate learning persists, suppresses and resets");
    Ok(())
}

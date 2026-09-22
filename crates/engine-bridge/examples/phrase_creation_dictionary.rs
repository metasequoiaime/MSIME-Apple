//! Check automatic phrase creation against the pinned production dictionaries.
//!
//! When a candidate consumes only part of the input, the Engine keeps composing and remembers what
//! was picked; completing the rest stores the composed phrase in the user's dictionary. None of
//! that is observable without real dictionaries: an empty one offers no partial candidate to pick,
//! so the composition never splits and there is nothing to compose.
//!
//! Nor is it observable from the full input alone. The lattice answers any input with a
//! whole-sentence candidate, so `海滩跑步` leads the list whether or not it was ever stored. What
//! separates the two is the abbreviation: a stored phrase answers `htpb`, a regenerated sentence
//! does not.
use msime_engine_bridge::{prepare_options, EngineOptions, Session};

const KEYS: &str = "haitanpaobu";
const ABBREVIATION: &str = "htpb";
const PHRASE: &str = "海滩跑步";
const ONLINE_KEYS: &str = "qi'e'huan";
const ONLINE_ABBREVIATION: &str = "qeh";
const ONLINE_PHRASE: &str = "企鹅幻";
/// The first selection has to be the candidate that consumes part of the input rather than the
/// whole-sentence one the lattice puts first.
const PARTIAL: usize = 1;

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
            "phrase-fixture",
        )?;
        // `prepare_options` leaves this off, unlike the Engine's own default. Composing a phrase
        // with it off stores nothing, which is the second half of this probe.
        options.learning = learning;
        Ok(options)
    }

    fn candidates(&self, keys: &str) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(false)?)?;
        for character in keys.bytes() {
            session.character(character, false)?;
        }
        Ok(session.snapshot()?.candidates)
    }

    /// Pick the partial candidate, then take the leading one until the input is used up.
    fn compose(&self, learning: bool) -> Result<String, Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(learning)?)?;
        for character in KEYS.bytes() {
            session.character(character, false)?;
        }
        let mut composed = String::new();
        let mut index = PARTIAL;
        while !session.snapshot()?.editing_text.is_empty() {
            let result = session.select(index)?;
            if !result.has_commit {
                return Err(format!("selection {index} committed nothing").into());
            }
            composed.push_str(&result.commit);
            index = 0;
        }
        Ok(composed)
    }

    /// Select the whole-sentence candidate directly, without first creating a phrase prefix.
    fn select_sentence(&self, learning: bool) -> Result<u8, Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(learning)?)?;
        for character in KEYS.bytes() {
            session.character(character, false)?;
        }
        let snapshot = session.snapshot()?;
        let index = snapshot
            .candidates
            .iter()
            .position(|candidate| candidate == PHRASE)
            .ok_or_else(|| format!("the sentence was not offered: {:?}", snapshot.candidates))?;
        let source = *snapshot
            .candidate_sources
            .get(index)
            .ok_or("the sentence has no source")?;
        // CandidateSource::Generated and CandidateSource::Fallback are 8 and 9. A packaged or
        // already learned dictionary row would not exercise standalone sentence learning.
        if source != 8 && source != 9 {
            return Err(
                format!("the sentence came from source {source}, not a generated path").into(),
            );
        }
        let committed = session.select(index)?;
        if !committed.has_commit || committed.commit != PHRASE {
            return Err(format!("selecting the sentence committed {:?}", committed.commit).into());
        }
        Ok(source)
    }

    /// Inject and select an online row whose explicit segmentation differs from the greedy cut.
    fn select_online_sentence(&self) -> Result<(), Box<dyn std::error::Error>> {
        let mut session = Session::new(&self.options(true)?)?;
        for character in ONLINE_KEYS.bytes() {
            session.character(character, false)?;
        }
        let query = session.online_query()?;
        if !query.available || query.query_text != ONLINE_KEYS {
            return Err(format!(
                "manual segmentation was not preserved: {}",
                query.query_text
            )
            .into());
        }
        if !session.apply_online_candidate(&query, ONLINE_PHRASE, 1)? {
            return Err("the synthetic AI candidate was rejected".into());
        }
        let snapshot = session.snapshot()?;
        let index = snapshot
            .candidates
            .iter()
            .position(|candidate| candidate == ONLINE_PHRASE)
            .ok_or("the synthetic AI candidate disappeared")?;
        let committed = session.select(index)?;
        if !committed.has_commit || committed.commit != ONLINE_PHRASE {
            return Err("the synthetic AI candidate was not committed".into());
        }
        Ok(())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: phrase_creation_dictionary <verified-resources>")?,
    )?;

    let learning = Store::new(&resources)?;
    assert!(
        !learning
            .candidates(ABBREVIATION)?
            .contains(&PHRASE.to_string()),
        "the abbreviation already offered the phrase before anything was composed"
    );
    let composed = learning.compose(true)?;
    assert_eq!(
        composed, PHRASE,
        "the parts did not compose into the phrase"
    );
    // The phrase is now a dictionary entry, so the abbreviation reaches it. Before composing, the
    // same query answered with unrelated words.
    assert!(
        learning
            .candidates(ABBREVIATION)?
            .contains(&PHRASE.to_string()),
        "the composed phrase was not stored: {:?}",
        learning.candidates(ABBREVIATION)?
    );

    // With learning off the same composition commits the same text and stores nothing. A separate
    // store, because the question is what was written, and the one above has been written to.
    let forgetting = Store::new(&resources)?;
    assert_eq!(forgetting.compose(false)?, PHRASE);
    assert!(
        !forgetting
            .candidates(ABBREVIATION)?
            .contains(&PHRASE.to_string()),
        "a phrase was stored while learning was turned off"
    );

    // The Windows source also learns a Generated/Fallback sentence selected as one candidate,
    // without a preceding partial selection. It is creation rather than frequency adjustment:
    // generated rows do not exist in SQLite yet, so changing their weight cannot persist them.
    let standalone = Store::new(&resources)?;
    assert!(!standalone
        .candidates(ABBREVIATION)?
        .contains(&PHRASE.to_string()));
    let source = standalone.select_sentence(true)?;
    assert!(
        standalone
            .candidates(ABBREVIATION)?
            .contains(&PHRASE.to_string()),
        "the directly selected source-{source} sentence was not stored"
    );

    let standalone_forgetting = Store::new(&resources)?;
    standalone_forgetting.select_sentence(false)?;
    assert!(
        !standalone_forgetting
            .candidates(ABBREVIATION)?
            .contains(&PHRASE.to_string()),
        "a directly selected sentence was stored while learning was turned off"
    );

    // Cloud/AI rows do not carry canonical_pinyin themselves. The session must use its explicit
    // segmentation as the storage key, and the strict canonical insertion path must not erase and
    // greedily re-cut it (qi'e'huan would otherwise become qie'huan and fail the 3-character check).
    let online = Store::new(&resources)?;
    assert!(!online
        .candidates(ONLINE_ABBREVIATION)?
        .contains(&ONLINE_PHRASE.to_string()));
    online.select_online_sentence()?;
    assert!(
        online
            .candidates(ONLINE_ABBREVIATION)?
            .contains(&ONLINE_PHRASE.to_string()),
        "the online phrase was not stored under its explicit segmentation"
    );

    println!("composed, standalone and online sentence candidates learn with canonical readings");
    Ok(())
}

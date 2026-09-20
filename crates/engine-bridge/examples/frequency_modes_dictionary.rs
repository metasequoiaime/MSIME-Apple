//! Check the five candidate frequency-adjustment modes against the pinned dictionaries.
//!
//! Each mode moves a chosen candidate by a different rule, so telling them apart needs a candidate
//! list long enough for the rules to disagree - which a synthetic dictionary does not provide. The
//! two ranks below were picked so that every mode lands somewhere different from every other:
//! halving rank 20 gives 10 while promoting gives 4, and at rank 3 halving gives 1 while the
//! linear step gives 2.
//!
//! Ranks are counted among dictionary candidates only. The list interleaves others - an English
//! candidate sits at display position 1 for this input - and those do not take part in frequency
//! adjustment, so counting display positions would make the rules look inconsistent.
use msime_engine_bridge::{prepare_options, Session};

const KEYS: &[u8] = b"shi";
/// `CandidateSource::Database`, the only source frequency adjustment applies to.
const DATABASE: u8 = 0;

struct Probe {
    resources: std::path::PathBuf,
    temporary: tempfile::TempDir,
    mode: &'static str,
}

impl Probe {
    fn new(
        resources: &std::path::Path,
        mode: &'static str,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            resources: resources.to_path_buf(),
            temporary: tempfile::tempdir()?,
            mode,
        })
    }

    fn session(&self) -> Result<Session, Box<dyn std::error::Error>> {
        let mut options = prepare_options(
            self.resources
                .to_str()
                .ok_or("resource path is not UTF-8")?,
            self.temporary.path().join("user").to_str().unwrap(),
            self.temporary.path().join("cache").to_str().unwrap(),
            "frequency-fixture",
        )?;
        // Adjustment is a form of learning; with learning off nothing is written whatever the mode.
        options.learning = true;
        options.frequency_mode = self.mode.into();
        options.frequency_trigger_count = 1;
        options.frequency_linear_step = 1;
        Ok(Session::new(&options)?)
    }

    /// Type the input and return the candidates together with their display positions, keeping only
    /// the dictionary ones.
    fn ranked(session: &mut Session) -> Result<Vec<(usize, String)>, Box<dyn std::error::Error>> {
        for character in KEYS {
            session.character(*character, false)?;
        }
        let snapshot = session.snapshot()?;
        Ok(snapshot
            .candidates
            .into_iter()
            .zip(snapshot.candidate_sources)
            .enumerate()
            .filter(|(_, (_, source))| *source == DATABASE)
            .map(|(display, (word, _))| (display, word))
            .collect())
    }

    /// Select the candidate at `rank` among dictionary candidates, then report where it sits when
    /// the input is typed again in a new session.
    fn adjust(&self, rank: usize) -> Result<usize, Box<dyn std::error::Error>> {
        let mut session = self.session()?;
        let before = Self::ranked(&mut session)?;
        let (display, word) = before
            .get(rank)
            .ok_or_else(|| format!("the dictionary offered fewer than {} candidates", rank + 1))?
            .clone();
        let committed = session.select(display)?;
        if committed.commit != word {
            return Err(format!("selecting {word} committed {:?}", committed.commit).into());
        }
        drop(session);
        let mut after_session = self.session()?;
        let after = Self::ranked(&mut after_session)?;
        after
            .iter()
            .position(|(_, candidate)| *candidate == word)
            .ok_or_else(|| format!("{word} is no longer offered under {}", self.mode).into())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: frequency_modes_dictionary <verified-resources>")?,
    )?;

    // (mode, rank 3 lands at, rank 20 lands at), following the documented rules:
    // disabled changes nothing; pin goes to the front; halving moves to the midpoint; the linear
    // step moves one place with the step set to one; promoting moves up one inside the top five and
    // lifts anything below it to fifth place.
    for (mode, from_three, from_twenty) in [
        ("disabled", 3, 20),
        ("pin", 0, 0),
        ("halve", 1, 10),
        ("linear", 2, 19),
        ("promote", 2, 4),
    ] {
        let probe = Probe::new(&resources, mode)?;
        let three = probe.adjust(3)?;
        assert_eq!(three, from_three, "{mode} moved rank 3 to {three}");
        let twenty = probe.adjust(20)?;
        assert_eq!(twenty, from_twenty, "{mode} moved rank 20 to {twenty}");
    }

    println!("all five frequency modes move candidates by their own rule");
    Ok(())
}

//! Check the mixed-input trigger length against the pinned dictionaries.
//!
//! English candidates join the pinyin list once the letters reach the configured length, which the
//! source documents as settable from one to eight. Checking it needs the real English dictionary:
//! with an empty one nothing appears at any length, so every threshold looks the same.
//!
//! That is also the trap this probe has to avoid. "No English candidate" has two causes - the
//! threshold not being met, and the dictionary having no word with that prefix - and a test that
//! cannot tell them apart would pass with the feature switched off. Every negative case here is
//! paired with a positive one over the same letters.
use msime_engine_bridge::{prepare_options, Session};

struct Probe {
    resources: std::path::PathBuf,
    temporary: tempfile::TempDir,
    sequence: usize,
}

/// `CandidateSource::English`.
const ENGLISH: u8 = 4;

impl Probe {
    fn new(resources: std::path::PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            resources,
            temporary: tempfile::tempdir()?,
            sequence: 0,
        })
    }

    fn english(
        &mut self,
        minimum_prefix: u8,
        mixed: bool,
        keys: &str,
    ) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        self.sequence += 1;
        let slot = self.sequence;
        let mut options = prepare_options(
            self.resources
                .to_str()
                .ok_or("resource path is not UTF-8")?,
            self.temporary
                .path()
                .join(format!("user-{slot}"))
                .to_str()
                .unwrap(),
            self.temporary
                .path()
                .join(format!("cache-{slot}"))
                .to_str()
                .unwrap(),
            "mixed-input-fixture",
        )?;
        options.learning = false;
        options.mixed_english = mixed;
        options.english_minimum_prefix = minimum_prefix;
        let mut session = Session::new(&options)?;
        for character in keys.bytes() {
            session.character(character, false)?;
        }
        let snapshot = session.snapshot()?;
        Ok(snapshot
            .candidates
            .into_iter()
            .zip(snapshot.candidate_sources)
            .filter(|(_, source)| *source == ENGLISH)
            .map(|(word, _)| word)
            .collect())
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: mixed_input_dictionary <verified-resources>")?,
    )?;
    let mut probe = Probe::new(resources)?;

    // Each threshold: one letter short gives nothing, and the same letters plus one give English
    // candidates. The pair is what makes the empty answer mean "not yet" rather than "never".
    for (minimum_prefix, short, met) in [(2u8, "s", "sh"), (3, "sh", "shi")] {
        let below = probe.english(minimum_prefix, true, short)?;
        assert!(
            below.is_empty(),
            "prefix {minimum_prefix} offered English for {short}: {below:?}"
        );
        let at = probe.english(minimum_prefix, true, met)?;
        assert!(
            !at.is_empty(),
            "prefix {minimum_prefix} offered no English for {met}"
        );
        assert!(
            at.iter().all(|word| word.starts_with(met)),
            "prefix {minimum_prefix} offered English that does not continue {met}: {at:?}"
        );
    }

    // Raising the threshold past the letters typed takes the same candidates away again.
    let raised = probe.english(4, true, "shi")?;
    assert!(
        raised.is_empty(),
        "a threshold of four answered three letters: {raised:?}"
    );

    // Switched off, length stops mattering: letters that produced candidates above now produce
    // none. Without this the whole probe would pass against a build that ignores the setting.
    for keys in ["sh", "shi"] {
        let off = probe.english(2, false, keys)?;
        assert!(
            off.is_empty(),
            "mixed input was off and {keys} still offered English: {off:?}"
        );
    }

    println!("mixed input waits for the configured number of letters");
    Ok(())
}

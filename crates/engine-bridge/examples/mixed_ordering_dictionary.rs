//! Check where emoji and kaomoji land among the candidates, against the pinned dictionaries.
//!
//! The source states the rule as: emoji are inserted after the English candidates, and kaomoji
//! after the emoji. Its own implementation is more specific - one of each is placed near the head,
//! in that order, and the rest are appended grouped by kind - but the part a user sees, and the
//! part worth pinning here, is the relative order of the first of each kind.
//!
//! None of it is observable without real dictionaries: the emoji and kaomoji tables are what supply
//! the candidates being ordered.
use msime_engine_bridge::{prepare_options, Session};

const KEYS: &str = "haha";
const ENGLISH: u8 = 4;
const EMOJI: u8 = 6;
const KAOMOJI: u8 = 7;

struct Probe {
    resources: std::path::PathBuf,
    temporary: tempfile::TempDir,
    sequence: usize,
}

impl Probe {
    fn new(resources: std::path::PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            resources,
            temporary: tempfile::tempdir()?,
            sequence: 0,
        })
    }

    fn sources(
        &mut self,
        emoji: bool,
        kaomoji: bool,
    ) -> Result<Vec<u8>, Box<dyn std::error::Error>> {
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
            "mixed-ordering-fixture",
        )?;
        options.learning = false;
        options.mixed_english = true;
        options.english_minimum_prefix = 2;
        options.mixed_emoji = emoji;
        options.mixed_kaomoji = kaomoji;
        let mut session = Session::new(&options)?;
        for character in KEYS.bytes() {
            session.character(character, false)?;
        }
        Ok(session.snapshot()?.candidate_sources)
    }
}

fn first(sources: &[u8], kind: u8) -> Option<usize> {
    sources.iter().position(|source| *source == kind)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: mixed_ordering_dictionary <verified-resources>")?,
    )?;
    let mut probe = Probe::new(resources)?;

    let all = probe.sources(true, true)?;
    let english = first(&all, ENGLISH).ok_or("no English candidate to order against")?;
    let emoji = first(&all, EMOJI).ok_or("no emoji candidate")?;
    let kaomoji = first(&all, KAOMOJI).ok_or("no kaomoji candidate")?;
    assert!(
        english < emoji,
        "emoji {emoji} came before English {english}: {all:?}"
    );
    assert!(
        emoji < kaomoji,
        "kaomoji {kaomoji} came before emoji {emoji}: {all:?}"
    );

    // Each switch removes only its own kind. Without this the ordering above would also hold for a
    // build that ignored the switches, since it only says where things are when they are present.
    let without_emoji = probe.sources(false, true)?;
    assert!(
        first(&without_emoji, EMOJI).is_none(),
        "emoji appeared with mixed emoji off"
    );
    assert!(
        first(&without_emoji, KAOMOJI).is_some(),
        "kaomoji left with only emoji turned off"
    );
    assert!(
        first(&without_emoji, ENGLISH).is_some(),
        "English left with only emoji turned off"
    );

    let without_kaomoji = probe.sources(true, false)?;
    assert!(
        first(&without_kaomoji, KAOMOJI).is_none(),
        "kaomoji appeared with mixed kaomoji off"
    );
    assert!(
        first(&without_kaomoji, EMOJI).is_some(),
        "emoji left with only kaomoji turned off"
    );

    // With emoji gone, kaomoji move up to where the emoji used to start rather than staying put.
    assert!(
        first(&without_emoji, KAOMOJI) <= Some(emoji),
        "kaomoji did not take the emoji's place: {without_emoji:?}"
    );

    println!("emoji follow the English candidates and kaomoji follow the emoji");
    Ok(())
}

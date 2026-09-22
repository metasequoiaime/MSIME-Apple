//! Check every input scheme against the pinned production dictionaries.
//!
//! The scheme unit tests build a synthetic sqlite dictionary, which is enough to prove the spelling
//! parser splits syllables but says nothing about whether a scheme reaches real entries: an empty
//! table answers "no candidates" for correct and incorrect spellings alike. This probe therefore
//! takes a resource directory staged from `resources/desktop-dictionary.lock.json`.
use msime_engine_bridge::{prepare_options, Session};

const QUANPIN: u8 = 0;
const SHUANGPIN: u8 = 1;
const WUBI: u8 = 2;
const JAPANESE_ROMAJI: u8 = 3;

struct Probe {
    resources: std::path::PathBuf,
    temporary: tempfile::TempDir,
    sequence: usize,
}

struct Reading {
    preedit: String,
    reading: String,
    candidates: Vec<String>,
}

impl Reading {
    fn offers(&self, word: &str) -> bool {
        self.candidates.iter().any(|candidate| candidate == word)
    }
    fn first(&self) -> &str {
        self.candidates.first().map(String::as_str).unwrap_or("")
    }
}

impl Probe {
    fn new(resources: std::path::PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            resources,
            temporary: tempfile::tempdir()?,
            sequence: 0,
        })
    }

    /// Each call gets its own user and cache directories: learning from one probe must not decide
    /// the candidate order seen by the next.
    /// Type `keys`, then ask the same session to hand over what it withheld. Answers the candidate
    /// count before, whether the Engine reported growth, and the count after.
    fn read_expanding(
        &mut self,
        scheme: u8,
        profile: u8,
        keys: &str,
    ) -> Result<(usize, bool, usize), Box<dyn std::error::Error>> {
        let mut session = self.session(scheme, profile)?;
        for character in keys.bytes() {
            session.character(character, false)?;
        }
        let before = session.snapshot()?.candidates.len();
        let grew = session.expand_initial_candidates()?;
        Ok((before, grew, session.snapshot()?.candidates.len()))
    }

    fn session(&mut self, scheme: u8, profile: u8) -> Result<Session, Box<dyn std::error::Error>> {
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
            "schemes-fixture",
        )?;
        options.scheme = scheme;
        options.shuangpin_profile = profile;
        Ok(Session::new(&options)?)
    }

    fn read(
        &mut self,
        scheme: u8,
        profile: u8,
        keys: &str,
    ) -> Result<Reading, Box<dyn std::error::Error>> {
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
            "schemes-fixture",
        )?;
        options.scheme = scheme;
        options.shuangpin_profile = profile;
        let mut session = Session::new(&options)?;
        for character in keys.bytes() {
            session.character(character, false)?;
        }
        let snapshot = session.snapshot()?;
        Ok(Reading {
            preedit: snapshot.preedit,
            reading: snapshot.reading,
            candidates: snapshot.candidates,
        })
    }
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: schemes_dictionary <verified-resources>")?,
    )?;
    let mut probe = Probe::new(resources)?;

    let quanpin = probe.read(QUANPIN, 0, "nihao")?;
    assert_eq!(
        quanpin.first(),
        "你好",
        "quanpin nihao: {:?}",
        quanpin.candidates
    );

    // Both spellings of a ü final have to reach the same entry. Upstream rewrites `nve` into `nue`
    // before handing the syllable to its decoder; this Engine accepts either, so the rewrite is not
    // a gap here. An empty dictionary cannot tell the two apart, which is why the question stayed
    // open until this probe: it answers "no candidates" for every spelling.
    for (v_form, u_form, word) in [("nve", "nue", "虐"), ("lve", "lue", "略")] {
        let v_reading = probe.read(QUANPIN, 0, v_form)?;
        let u_reading = probe.read(QUANPIN, 0, u_form)?;
        assert_eq!(
            v_reading.first(),
            word,
            "{v_form}: {:?}",
            v_reading.candidates
        );
        assert_eq!(
            u_reading.first(),
            word,
            "{u_form}: {:?}",
            u_reading.candidates
        );
    }
    // A `u` that is really ü after j/q/x, which has no second spelling to fall back on.
    for (keys, word) in [
        ("ju", "句"),
        ("qu", "去"),
        ("xu", "许"),
        ("jue", "觉"),
        ("quan", "全"),
    ] {
        let reading = probe.read(QUANPIN, 0, keys)?;
        assert_eq!(reading.first(), word, "{keys}: {:?}", reading.candidates);
    }

    // `ni` is n + i in all four profiles, so one input exercises every profile's path into the
    // dictionary without hardcoding four different final tables.
    for profile in 0..4 {
        let reading = probe.read(SHUANGPIN, profile, "ni")?;
        assert!(
            reading.offers("你"),
            "shuangpin profile {profile}: {:?}",
            reading.candidates
        );
    }
    // `yo` is a complete zero-initial syllable in every shipped profile. A synthetic empty
    // dictionary can leave a non-empty preedit even when the parser split it incorrectly, so pin
    // both the visible boundary and the real dictionary row for 哟.
    for profile in 0..4 {
        let reading = probe.read(SHUANGPIN, profile, "yo")?;
        assert_eq!(
            reading.preedit, "yo",
            "shuangpin profile {profile} split the complete yo syllable"
        );
        assert!(
            reading.offers("哟"),
            "shuangpin profile {profile} did not reach yo: {:?}",
            reading.candidates
        );
    }
    // Microsoft is the one profile whose finals this repository spells out, so it also gets a
    // two-syllable reading: `hk` is `hao`, and the preedit has to show the syllable split.
    let microsoft = probe.read(SHUANGPIN, 3, "nihk")?;
    assert_eq!(microsoft.preedit, "ni'hao", "microsoft shuangpin preedit");
    assert_eq!(
        microsoft.first(),
        "你好",
        "microsoft shuangpin: {:?}",
        microsoft.candidates
    );

    // Wubi 键名汉字: the character living on a key is typed by pressing that key four times, which
    // is stable across wubi86 tables and needs no stroke decomposition to state.
    for (keys, word) in [("gggg", "王"), ("hhhh", "目"), ("aaaa", "工")] {
        let reading = probe.read(WUBI, 0, keys)?;
        assert_eq!(
            reading.first(),
            word,
            "wubi {keys}: {:?}",
            reading.candidates
        );
    }

    // Japanese carries a kana reading beside the candidates; the other schemes leave it empty.
    for (keys, kana, word) in [("nihon", "にほん", "日本"), ("sakura", "さくら", "さくら")]
    {
        let reading = probe.read(JAPANESE_ROMAJI, 0, keys)?;
        assert_eq!(reading.reading, kana, "japanese {keys} reading");
        assert!(
            reading.offers(word),
            "japanese {keys}: {:?}",
            reading.candidates
        );
    }
    let chinese = probe.read(QUANPIN, 0, "nihao")?;
    assert!(
        chinese.reading.is_empty(),
        "quanpin carried a kana reading: {}",
        chinese.reading
    );

    // A single letter is the one query the Engine caps, at twenty-four candidates, handing over the
    // rest only when asked. Reading the cap here rather than trusting the number keeps this honest
    // if the Engine ever changes it: what matters is that asking produces more than the first
    // answer held.
    let (capped, grew, expanded) = probe.read_expanding(QUANPIN, 0, "j")?;
    assert!(grew, "the Engine withheld nothing for a single letter");
    assert!(
        expanded > capped,
        "expansion reported growth but the list is still {expanded} long"
    );

    println!("all schemes reached the pinned dictionaries");
    Ok(())
}

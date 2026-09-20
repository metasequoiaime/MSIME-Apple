//! Verify independent local-mode entry gates with isolated production resources.
use msime_engine_bridge::{prepare_options, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: local_modes_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "local-modes-fixture",
    )?;
    let modes = [
        (b'U', "unicode"),
        (b'T', "date_time"),
        (b'K', "quick_phrase"),
        (b'E', "emoji"),
        (b'M', "kaomoji"),
        (b'J', "super_jianpin"),
        (b'Y', "temporary_english"),
        (b'R', "temporary_japanese"),
    ];
    for (index, (letter, name)) in modes.into_iter().enumerate() {
        let mut enabled = Session::new(&options)?;
        enabled.character(letter, true)?;
        assert_eq!(enabled.snapshot()?.local_mode, name);
        if letter == b'U' {
            for digit in b"4e2d" {
                enabled.character(*digit, false)?;
            }
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert_eq!(committed.commit, "中");
        }
        if letter == b'T' {
            for character in b"rq" {
                enabled.character(*character, false)?;
            }
            assert!(!enabled.snapshot()?.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'K' {
            enabled.character(b'a', false)?;
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'E' {
            for character in b"XIAOLIAN" {
                enabled.character(*character, false)?;
            }
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'M' {
            for character in b"hx" {
                enabled.character(*character, false)?;
            }
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'J' {
            for character in b"nh" {
                enabled.character(*character, false)?;
            }
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'Y' {
            for character in b"he" {
                enabled.character(*character, false)?;
            }
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        if letter == b'R' {
            for character in b"ka" {
                enabled.character(*character, false)?;
            }
            let snapshot = enabled.snapshot()?;
            assert!(!snapshot.candidates.is_empty());
            let committed = enabled.select(0)?;
            assert!(committed.has_commit);
            assert!(!committed.commit.is_empty());
        }
        let mut disabled = options.clone();
        match index {
            0 => disabled.local_unicode = false,
            1 => disabled.local_date_time = false,
            2 => disabled.local_quick_phrase = false,
            3 => disabled.local_emoji = false,
            4 => disabled.local_kaomoji = false,
            5 => disabled.local_super_jianpin = false,
            6 => disabled.local_temporary_english = false,
            7 => disabled.local_temporary_japanese = false,
            _ => unreachable!(),
        }
        let mut session = Session::new(&disabled)?;
        session.character(letter, true)?;
        assert_eq!(session.snapshot()?.local_mode, "none");
        let (other_letter, other_name) = modes[(index + 1) % modes.len()];
        let mut other = Session::new(&disabled)?;
        other.character(other_letter, true)?;
        assert_eq!(other.snapshot()?.local_mode, other_name);
        println!("{name}: enabled entry and disabled fallback passed");
    }
    documented_boundaries(&resources)?;
    Ok(())
}

/// The entry checks above only ask whether a mode produced something. These take the spellings the
/// source documents for two of them and check what comes out.
fn documented_boundaries(resources: &std::path::Path) -> Result<(), Box<dyn std::error::Error>> {
    let temporary = tempfile::tempdir()?;
    let mut sequence = 0usize;
    let mut typed = |letter: u8, keys: &str| -> Result<Vec<String>, Box<dyn std::error::Error>> {
        sequence += 1;
        let options = prepare_options(
            resources.to_str().ok_or("resource path is not UTF-8")?,
            temporary
                .path()
                .join(format!("user-{sequence}"))
                .to_str()
                .unwrap(),
            temporary
                .path()
                .join(format!("cache-{sequence}"))
                .to_str()
                .unwrap(),
            "local-modes-fixture",
        )?;
        let mut session = Session::new(&options)?;
        session.character(letter, true)?;
        for character in keys.bytes() {
            session.character(character, false)?;
        }
        let candidates = session.snapshot()?.candidates;
        if candidates.is_empty() {
            return Err(format!("{} offered nothing for {keys}", letter as char).into());
        }
        Ok(candidates)
    };

    // Date-time takes three spellings for each of its three answers. Only `rq` was covered before,
    // so eight of the nine documented ways in were never exercised.
    //
    // The three spellings of one answer have to agree, which is the check that they are aliases
    // rather than three things that happen to be non-empty. Time is compared only for shape: its
    // answer moves while this runs, so requiring the three to match would fail on a second boundary.
    let date: Vec<String> = ["rq", "riqi", "date"]
        .iter()
        .map(|keys| typed(b'T', keys).map(|list| list[0].clone()))
        .collect::<Result<_, _>>()?;
    assert!(
        date[0] == date[1] && date[1] == date[2],
        "date spellings disagreed: {date:?}"
    );
    let week: Vec<String> = ["xq", "xingqi", "week"]
        .iter()
        .map(|keys| typed(b'T', keys).map(|list| list[0].clone()))
        .collect::<Result<_, _>>()?;
    assert!(
        week[0] == week[1] && week[1] == week[2],
        "weekday spellings disagreed: {week:?}"
    );
    for keys in ["sj", "shijian", "time"] {
        assert!(!typed(b'T', keys)?[0].is_empty(), "{keys} offered no time");
    }
    assert_ne!(date[0], week[0], "date and weekday returned the same text");

    // Super-jianpin searches by initials: `nh` reaches 你好, whose two syllables start n and h.
    // Which of the matches leads is a ranking question - 女孩 does, here - so what is asserted is
    // that the initials search found it at all, and that nothing answering plain `nh` as pinyin
    // crowds it out.
    let jianpin = typed(b'J', "nh")?;
    assert!(
        jianpin.contains(&"你好".to_string()),
        "super-jianpin nh did not reach 你好: {:?}",
        &jianpin[..jianpin.len().min(8)]
    );
    assert!(
        jianpin.iter().take(8).all(|word| word.chars().count() >= 2),
        "super-jianpin nh offered a single character: {:?}",
        &jianpin[..jianpin.len().min(8)]
    );

    println!("date-time spellings and super-jianpin initials match the documented behaviour");
    Ok(())
}

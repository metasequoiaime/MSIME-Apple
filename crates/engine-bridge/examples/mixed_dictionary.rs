//! Verify mixed candidate switches against isolated locked dictionary copies.
use msime_engine_bridge::{prepare_options, EngineOptions, Session};

fn query(options: &EngineOptions) -> Result<Vec<String>, cxx::Exception> {
    let mut session = Session::new(options)?;
    session.character(b'h', false)?;
    session.character(b'a', false)?;
    Ok(session.snapshot()?.candidates)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: mixed_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "mixed-fixture",
    )?;
    options.helpcode = false;
    options.learning = false;
    options.mixed_english = false;
    for scheme in 0..4 {
        options.scheme = scheme;
        let baseline = query(&options)?;
        let mut leading = Vec::new();
        for source in 0..3 {
            let mut enabled = options.clone();
            enabled.mixed_english = source == 0;
            enabled.mixed_emoji = source == 1;
            enabled.mixed_kaomoji = source == 2;
            let actual = query(&enabled)?;
            if scheme >= 2 {
                assert_eq!(
                    actual, baseline,
                    "non-pinyin scheme must not mix candidates"
                );
                continue;
            }
            let additions: Vec<_> = actual
                .iter()
                .filter(|word| !baseline.contains(word))
                .collect();
            assert!(
                !additions.is_empty(),
                "source {source} has no fixture candidates"
            );
            assert_eq!(actual[0], baseline[0]);
            assert_eq!(&actual[1], additions[0]);
            leading.push(actual[1].clone());
            if source == 0 {
                assert!(additions.iter().all(|word| word.is_ascii()));
                enabled.english_minimum_prefix = 3;
                assert_eq!(
                    query(&enabled)?,
                    baseline,
                    "prefix threshold must suppress English"
                );
                enabled.english_minimum_prefix = 2;
            }
            let mut session = Session::new(&enabled)?;
            session.character(b'h', false)?;
            session.character(b'a', false)?;
            let result = session.select(1)?;
            assert!(
                result.has_commit && result.commit == actual[1] && result.diagnostic.is_empty()
            );
        }
        if scheme < 2 {
            let mut all = options.clone();
            all.mixed_english = true;
            all.mixed_emoji = true;
            all.mixed_kaomoji = true;
            let actual = query(&all)?;
            assert_eq!(
                &actual[1..4],
                leading.as_slice(),
                "English, emoji, kaomoji ordering"
            );
        }
        println!("scheme {scheme}: independent mixed sources, threshold and ordering passed");
    }
    Ok(())
}

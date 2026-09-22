//! Real-resource probe for the Google decoder's spelling of ü syllables.
use msime_engine_bridge::{prepare_options, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: google_umlaut_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("resource path is not UTF-8")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "google-umlaut-fixture",
    )?;
    options.scheme = 1;
    options.shuangpin_profile = 0;
    options.sentence_alternatives = true;

    let mut session = Session::new(&options)?;
    for key in b"ntdddswu" {
        session.character(*key, false)?;
    }
    let snapshot = session.snapshot()?;
    let rows: Vec<_> = snapshot
        .candidates
        .iter()
        .zip(&snapshot.candidate_sources)
        .map(|(word, source)| format!("{word}[source={source}]"))
        .collect();
    println!("{}", rows.join(", "));
    if !snapshot.candidates.iter().any(|word| word == "虐待动物") {
        return Err("Google decoder did not offer 虐待动物 for Xiaohe ntdddswu".into());
    }
    if snapshot
        .candidates
        .iter()
        .zip(&snapshot.candidate_sources)
        .any(|(word, source)| *source == 9 && word != "虐待动物")
    {
        return Err("Google decoder split nve into nv + e".into());
    }

    let mut quanpin = options.clone();
    quanpin.scheme = 0;
    quanpin.sentence_alternatives = false;
    let mut session = Session::new(&quanpin)?;
    for key in b"nu'e" {
        session.character(*key, false)?;
    }
    let snapshot = session.snapshot()?;
    if snapshot
        .candidates
        .iter()
        .zip(&snapshot.candidate_sources)
        .any(|(word, source)| word == "虐" && *source == 9)
    {
        return Err("manual nu'e was flattened into the single syllable nue".into());
    }
    Ok(())
}

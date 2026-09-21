//! Real-resource regression probe for whole-sentence reading fidelity.
use msime_engine_bridge::{prepare_options, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: lattice_reading_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("resource path is not UTF-8")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "lattice-reading-fixture",
    )?;
    options.sentence_alternatives = true;

    for (keys, rejected) in [("gunqi", "卷七"), ("nengfasheng", "而发生")] {
        let mut session = Session::new(&options)?;
        for key in keys.bytes() {
            session.character(key, false)?;
        }
        let snapshot = session.snapshot()?;
        let rows: Vec<_> = snapshot
            .candidates
            .iter()
            .zip(&snapshot.candidate_sources)
            .zip(&snapshot.candidate_codes)
            .map(|((word, source), code)| format!("{word}[source={source},code={code}]"))
            .collect();
        println!("{keys}: {}", rows.join(", "));
        if (keys == "gunqi"
            && snapshot
                .candidates
                .first()
                .is_some_and(|word| word == "滚球" || word == "棍球"))
            || snapshot
                .candidates
                .first()
                .is_some_and(|word| word == rejected)
            || snapshot
                .candidates
                .iter()
                .zip(&snapshot.candidate_sources)
                .any(|(word, source)| word == rejected && *source == 8)
        {
            return Err(format!("rare reading {rejected} won or was generated for {keys}").into());
        }
    }
    Ok(())
}

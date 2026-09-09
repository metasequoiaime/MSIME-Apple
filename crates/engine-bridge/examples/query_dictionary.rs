//! Real dictionary integration probe; temporary user/cache directories are isolated.
use msime_engine_bridge::{prepare_options, CandidateEdge, Session};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::env::args_os()
        .nth(1)
        .ok_or("usage: query_dictionary <verified-dictionary-directory>")?;
    let resources = std::fs::canonicalize(resources)?;
    let temporary = tempfile::tempdir()?;
    let options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "integration-probe",
    )?;
    let mut session = Session::new(&options)?;
    for character in b"nihao" {
        session.character(*character, false)?;
    }
    let snapshot = session.snapshot()?;
    let index = snapshot
        .candidates
        .iter()
        .position(|word| word == "你好")
        .ok_or("expected phrase missing from published dictionary")?;
    let selected = session.select(index)?;
    if !selected.has_commit || selected.commit != "你好" {
        return Err("published dictionary selection failed".into());
    }
    drop(session);
    for (edge, expected) in [
        (CandidateEdge::FirstHan, "你"),
        (CandidateEdge::LastHan, "好"),
    ] {
        let mut session = Session::new(&options)?;
        for character in b"nihao" {
            session.character(*character, false)?;
        }
        let snapshot = session.snapshot()?;
        let index = snapshot
            .candidates
            .iter()
            .position(|word| word == "你好")
            .ok_or("expected edge-selection phrase missing")?;
        let selected = session.select_edge(index, edge)?;
        if !selected.handled
            || !selected.has_commit
            || selected.commit != expected
            || !session.snapshot()?.editing_text.is_empty()
        {
            return Err("published dictionary edge selection failed".into());
        }
    }
    println!(
        "published dictionary: phrase and both Han edges committed; isolated generation prepared"
    );
    Ok(())
}

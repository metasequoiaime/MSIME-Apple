//! The alternative-segmentation slot lifts what cannot be seen, and leaves alone what can.
//!
//! `xian` reads either `xian` or `xi'an`, and one slot near the top of the list is kept for the
//! best word of the other reading so 西安 - position 16 on weight alone - is reachable without
//! paging. The slot used to claim any such word below index 1, which meant it also reordered words
//! already on the first page: it put 提案 ahead of 田 for `tian`, and, worse, it re-pinned any word
//! the user had promoted, because frequency ranks by weight and the slot recognises the heaviest
//! word of a reading group. Picking such a word once moved it to second place and nothing moved it
//! afterwards. See `scripts/apply_engine_alternative_segmentation_page.py`.
use msime_engine_bridge::{prepare_options, Session};

fn first_page(
    session: &mut Session,
    letters: &str,
) -> Result<Vec<String>, Box<dyn std::error::Error>> {
    for byte in letters.bytes() {
        session.character(byte, false)?;
    }
    let list = session.snapshot()?.candidates;
    Ok(list.into_iter().take(6).collect())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: alternative_segmentation_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "alt-segmentation-fixture",
    )?;
    options.helpcode = false;
    options.mixed_english = false;
    options.learning = false;

    // Still lifted: 西安 cannot be seen without paging, which is what the slot is for.
    let mut session = Session::new(&options)?;
    let xian = first_page(&mut session, "xian")?;
    assert_eq!(
        xian.iter().position(|word| word == "西安"),
        Some(1),
        "a reading off the first page is still lifted onto it: {xian:?}"
    );
    drop(session);

    // No longer reordered: 提案 is on the first page on weight alone, and the slot has no business
    // moving it ahead of a character the dictionary ranks above it.
    let mut session = Session::new(&options)?;
    let tian = first_page(&mut session, "tian")?;
    let field = tian
        .iter()
        .position(|word| word == "田")
        .ok_or("田 missing")?;
    let proposal = tian
        .iter()
        .position(|word| word == "提案")
        .ok_or("提案 missing")?;
    assert!(
        field < proposal,
        "a reading already on the first page keeps the rank its weight earned: {tian:?}"
    );
    drop(session);

    println!("alternative segmentation: lifts {xian:?}, leaves {tian:?} in weight order");
    Ok(())
}

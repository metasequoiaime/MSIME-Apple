//! 调频 ranks a pick against everything visible, and the basis comes from weight order.
//!
//! One candidate list mixes several dictionary keys - a re-segmentation puts 吉安 (`ji'an`) inside
//! the `jian` list - and the comparison set used to be walled off by syllable count, which capped
//! 吉安's learnable weight far below 见's and left it immovable however often it was picked. The
//! wall existed because the midpoint arithmetic assumed weight order and the displayed order is
//! not that. Sorting the set by weight restores the assumption at its source and lets the wall
//! come down. See `scripts/apply_engine_frequency_comparison_set.py`.
use msime_engine_bridge::{prepare_options, Session};

fn climb(
    resources: &std::path::Path,
    letters: &str,
    word: &str,
    rounds: usize,
) -> Result<Vec<usize>, Box<dyn std::error::Error>> {
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "frequency-comparison-fixture",
    )?;
    options.helpcode = false;
    options.mixed_english = false;
    options.learning = true;
    options.frequency_mode = "promote".into();
    options.frequency_trigger_count = 1;
    let mut seen = Vec::new();
    for _ in 0..rounds {
        let mut session = Session::new(&options)?;
        for byte in letters.bytes() {
            session.character(byte, false)?;
        }
        let list = session.snapshot()?.candidates;
        let at = list.iter().position(|w| w == word).ok_or("word missing")?;
        seen.push(at);
        let picked = session.select(at)?;
        assert!(picked.has_commit && picked.commit == word);
    }
    Ok(seen)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: frequency_comparison_set_dictionary <verified-resources>")?,
    )?;

    // 吉安 is weight 1 in the shipped dictionary and starts at 74, far behind 见 at 3460998. Picked
    // repeatedly it now walks all the way to the top; walled into its own syllable group it used to
    // stall around 32 and never move again.
    let jian = climb(&resources, "jian", "吉安", 6)?;
    assert_eq!(
        jian.first().copied(),
        Some(74),
        "the shipped dictionary moved; this fixture is about a candidate that starts far down"
    );
    assert_eq!(
        jian.last().copied(),
        Some(0),
        "picking a re-segmentation candidate must be able to reach the top: {jian:?}"
    );
    assert!(
        jian.windows(2).all(|pair| pair[1] <= pair[0]),
        "and it must never go backwards: {jian:?}"
    );

    // The guard the wall was built for: ranking must not take its basis from a row sitting above
    // its own weight. 写 climbs one place per pick and stops at the top; the defect wrote it a
    // weight of 506 - 西鄂's 6 plus 500 - which is not a rank at all.
    let xie = climb(&resources, "xie", "写", 5)?;
    assert_eq!(
        xie,
        vec![3, 2, 1, 0, 0],
        "one place per pick, then the top: {xie:?}"
    );

    println!("frequency comparison set: 吉安 {jian:?}, 写 {xie:?}");
    Ok(())
}

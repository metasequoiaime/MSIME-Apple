//! Times `hanzi_to_pinyin` per call, isolated from any session or typing.
//!
//! It exists because the function is not obviously expensive from its call sites and was measured
//! at milliseconds per call, while `msime_client_dictionary_validate` runs it in a loop over as
//! many as a thousand words. `harvest_eval_set` times it too, but from behind an engine session
//! and a reranking model, where a change is easy to misattribute — the first attempt at reading
//! this cost that way concluded the opposite of the truth because a test suite was running on the
//! same machine.
//!
//! Read the numbers as a ratio between two runs on a quiet machine, not as absolutes. Consecutive
//! runs of the same build varied by 3x here under load, and the mean over twenty calls is not
//! robust to that; what survives the noise is the difference between the two shapes below.
use std::path::Path;
use std::time::Instant;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::env::args()
        .nth(1)
        .ok_or("usage: pinyin_timing <resources>")?;
    let state = tempfile::tempdir()?;
    let generation = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../resources/desktop-dictionary.lock.json"),
    )?;
    let generation: serde_json::Value = serde_json::from_str(&generation)?;
    let generation = generation["source_commit"].as_str().ok_or("no commit")?;
    let options = msime_engine_bridge::prepare_options(
        &resources,
        state.path().join("user").to_str().ok_or("path")?,
        state.path().join("cache").to_str().ok_or("path")?,
        generation,
    )?;

    // Two shapes, because they take different paths inside: a word the dictionary holds whole
    // answers from the exact lookup, and a sentence it does not falls through to the
    // single-character map.
    let cases: [(&str, &str); 2] = [("词典命中", "你好"), ("回退到单字", "我明天准备去东京")];
    for (label, word) in cases {
        // First call separately: it is the one that would build a cache, and averaging it in
        // would hide whether later calls got cheaper.
        let started = Instant::now();
        let first = msime_engine_bridge::hanzi_to_pinyin(&options, word);
        let first_ms = started.elapsed().as_secs_f64() * 1000.0;

        let runs = 20;
        let started = Instant::now();
        for _ in 0..runs {
            let _ = msime_engine_bridge::hanzi_to_pinyin(&options, word);
        }
        let rest_ms = started.elapsed().as_secs_f64() * 1000.0 / f64::from(runs);
        println!(
            "{label:<12} {word:<10} -> {first:<28} 首次 {first_ms:7.2}ms  之后 {rest_ms:7.2}ms"
        );
    }
    Ok(())
}

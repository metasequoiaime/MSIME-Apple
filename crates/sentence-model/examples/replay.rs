//! Replays the candidate lists `convert_eval --dump` recorded and reports what reranking does.
//!
//! This exists to check the Rust forward pass against the Python one in `tools/sentence-model`. Both
//! read the same weights and the same cases, so the two tables have to agree; a port that merely
//! looks plausible on one hand-picked example is not evidence of anything.
//!
//! usage: replay <model.safetensors> <cases.jsonl>

use std::time::Instant;

use std::sync::Arc;

use msime_sentence_model::{Reranker, SentenceModel};

#[derive(serde::Deserialize)]
struct Candidate {
    text: String,
    source: u8,
}

#[derive(serde::Deserialize)]
struct Case {
    gold: String,
    #[serde(default)]
    context: String,
    candidates: Vec<Candidate>,
}

#[derive(Default)]
struct Bucket {
    cases: usize,
    before: usize,
    after: usize,
}

fn main() {
    let mut args = std::env::args().skip(1);
    let model_path = args
        .next()
        .expect("usage: replay <model.safetensors> <cases.jsonl>");
    let cases_path = args
        .next()
        .expect("usage: replay <model.safetensors> <cases.jsonl>");

    let bytes = std::fs::read(&model_path).expect("read model");
    let mut reranker = Reranker::new(Arc::new(SentenceModel::load(&bytes).expect("load model")));
    let text = std::fs::read_to_string(&cases_path).expect("read cases");

    let mut dictionary = Bucket::default();
    let mut decoded = Bucket::default();
    let mut elapsed = std::time::Duration::ZERO;
    let mut decisions = 0usize;

    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let case: Case = serde_json::from_str(line).expect("parse case");
        // The runtime criterion, not the evaluation's: the gate reads the source of the list's
        // leader, and the comparable set is the candidates matching the leader's length. The
        // evaluation could filter by the length of the correct answer; the input method cannot.
        let sources: Vec<u8> = case
            .candidates
            .iter()
            .map(|candidate| candidate.source)
            .collect();
        let texts: Vec<&str> = case
            .candidates
            .iter()
            .map(|candidate| candidate.text.as_str())
            .collect();
        let Some(&leader) = sources.first() else {
            continue;
        };
        let width = texts[0].chars().count();
        if texts
            .iter()
            .filter(|text| text.chars().count() == width)
            .count()
            < 2
        {
            continue;
        }

        let bucket = if msime_sentence_model::DICTIONARY_SOURCES.contains(&leader) {
            &mut dictionary
        } else {
            &mut decoded
        };
        bucket.cases += 1;
        bucket.before += usize::from(texts[0] == case.gold);

        let started = Instant::now();
        let chosen = reranker.best(&case.context, &texts, &sources).unwrap_or(0);
        elapsed += started.elapsed();
        decisions += 1;
        bucket.after += usize::from(texts[chosen] == case.gold);
    }

    println!(
        "{:<22}{:>7}{:>9}{:>10}{:>8}",
        "leading candidate", "n", "engine", "reranked", "delta"
    );
    let mut total = Bucket::default();
    for (name, bucket) in [("dictionary", &dictionary), ("decoded", &decoded)] {
        if bucket.cases == 0 {
            continue;
        }
        report(name, bucket);
        total.cases += bucket.cases;
        total.before += bucket.before;
        total.after += bucket.after;
    }
    report("all", &total);
    if decisions > 0 {
        println!(
            "\n{decisions} decisions, {:?} each on average",
            elapsed / decisions as u32
        );
    }
}

fn report(name: &str, bucket: &Bucket) {
    let cases = bucket.cases.max(1) as f64;
    let before = bucket.before as f64 / cases;
    let after = bucket.after as f64 / cases;
    println!(
        "{name:<22}{:>7}{before:>9.3}{after:>10.3}{:>+8.3}",
        bucket.cases,
        after - before
    );
}

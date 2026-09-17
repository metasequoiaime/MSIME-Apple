//! Measures how long one reranking decision takes, which is what decides whether the model can run
//! on the keystroke path or has to be moved off it.
//!
//! usage: bench <model.safetensors> [context] [candidate ...]

use std::time::Instant;

use msime_sentence_model::SentenceModel;

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args
        .next()
        .expect("usage: bench <model.safetensors> [context] [candidate ...]");
    let context = args.next().unwrap_or_default();
    let supplied: Vec<String> = args.collect();
    let candidates: Vec<&str> = if supplied.is_empty() {
        vec![
            "我今天去上班",
            "握紧天趣上班",
            "我今天去上版",
            "我今天趣上班",
            "握今天去上班",
            "我今添去上班",
            "我今天去伤班",
            "握紧天去上班",
            "我今天趣伤班",
        ]
    } else {
        supplied.iter().map(String::as_str).collect()
    };

    let started = Instant::now();
    let bytes = std::fs::read(&path).expect("read model");
    let model = SentenceModel::load(&bytes).expect("load model");
    println!(
        "load {:?} for {:.1} MB",
        started.elapsed(),
        bytes.len() as f64 / 1e6
    );
    println!("attribution: {}", model.attribution());

    // One untimed pass so the measurement is not dominated by first-touch page faults.
    let _ = model.score(&context, &candidates);

    for count in [3, 5, 9] {
        let subset = &candidates[..count.min(candidates.len())];
        let started = Instant::now();
        let runs = 5;
        for _ in 0..runs {
            let _ = model.score(&context, subset);
        }
        let each = started.elapsed() / runs;
        println!(
            "{} candidates, context {} chars: {each:?}",
            subset.len(),
            context.chars().count()
        );
    }

    let scores = model.score(&context, &candidates);
    let mut ranked: Vec<_> = candidates.iter().zip(&scores).collect();
    ranked.sort_by(|a, b| b.1.total_cmp(a.1));
    for (text, score) in ranked {
        println!("  {score:>8.4}  {text}");
    }
}

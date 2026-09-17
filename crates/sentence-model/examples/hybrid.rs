//! Sweeps ways of combining the model's opinion with the evidence the engine already has.
//!
//! The shipped rule is a hard gate: never touch a list whose leader is an exact dictionary hit,
//! and inside the rest let the model decide alone. That was chosen because letting the model decide
//! everywhere lost fourteen points of word accuracy. A hard gate is the limit of a soft one, though,
//! and a soft one can express things the gate cannot — promoting a dictionary candidate from third
//! place when the model is very confident, for instance, which the gate forbids outright.
//!
//! So the question is whether any weighting beats the gate. This answers it by scoring every
//! candidate with `model + rank * rank_weight + dictionary_weight` and reporting both buckets for a
//! grid of weights, against the recorded candidate lists.
//!
//! usage: hybrid <model.safetensors> <cases.jsonl>

use std::sync::Arc;

use msime_sentence_model::{Reranker, SentenceModel, DICTIONARY_SOURCES};

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

/// One comparable list, already scored by the model, kept so the grid does not re-run inference.
struct Scored {
    gold: String,
    texts: Vec<String>,
    sources: Vec<u8>,
    model: Vec<f32>,
    leader_is_dictionary: bool,
}

const RANK_WEIGHTS: [f32; 5] = [0.0, 0.1, 0.25, 0.5, 1.0];
const DICTIONARY_WEIGHTS: [f32; 5] = [0.0, 0.25, 0.5, 1.0, 2.0];

fn main() {
    let mut args = std::env::args().skip(1);
    let model_path = args
        .next()
        .expect("usage: hybrid <model.safetensors> <cases.jsonl>");
    let cases_path = args
        .next()
        .expect("usage: hybrid <model.safetensors> <cases.jsonl>");

    let bytes = std::fs::read(&model_path).expect("read model");
    let mut reranker = Reranker::new(Arc::new(SentenceModel::load(&bytes).expect("load model")));
    let text = std::fs::read_to_string(&cases_path).expect("read cases");

    let mut scored = Vec::new();
    for line in text.lines().filter(|line| !line.trim().is_empty()) {
        let case: Case = serde_json::from_str(line).expect("parse case");
        let Some(leader) = case.candidates.first() else {
            continue;
        };
        let width = leader.text.chars().count();
        let considered: Vec<&Candidate> = case
            .candidates
            .iter()
            .filter(|candidate| candidate.text.chars().count() == width)
            .take(9)
            .collect();
        if considered.len() < 2 {
            continue;
        }
        let texts: Vec<&str> = considered.iter().map(|c| c.text.as_str()).collect();
        let model = reranker.log_probabilities(&case.context, &texts);
        scored.push(Scored {
            gold: case.gold,
            texts: texts.iter().map(|t| (*t).to_owned()).collect(),
            sources: considered.iter().map(|c| c.source).collect(),
            model,
            leader_is_dictionary: DICTIONARY_SOURCES.contains(&leader.source),
        });
    }

    let engine = |bucket: bool| {
        let rows: Vec<&Scored> = scored
            .iter()
            .filter(|s| s.leader_is_dictionary == bucket)
            .collect();
        let hits = rows.iter().filter(|s| s.texts[0] == s.gold).count();
        (rows.len(), hits)
    };
    let (dictionary_n, dictionary_hits) = engine(true);
    let (decoded_n, decoded_hits) = engine(false);
    println!("cases: {dictionary_n} dictionary-led, {decoded_n} decoder-led");
    println!(
        "engine top-1: dictionary {:.3}, decoded {:.3}",
        dictionary_hits as f64 / dictionary_n.max(1) as f64,
        decoded_hits as f64 / decoded_n.max(1) as f64
    );

    // The shipped gate, for comparison: decoder-led lists are decided by the model alone and
    // dictionary-led lists are left exactly as the engine ordered them.
    let gate_decoded = scored
        .iter()
        .filter(|s| !s.leader_is_dictionary)
        .filter(|s| s.texts[argmax(&s.model)] == s.gold)
        .count();
    println!(
        "gate:         dictionary {:.3}, decoded {:.3}",
        dictionary_hits as f64 / dictionary_n.max(1) as f64,
        gate_decoded as f64 / decoded_n.max(1) as f64
    );

    println!(
        "\n{:>6}{:>7}  {:>12}{:>10}{:>10}",
        "rank", "dict", "dictionary", "decoded", "overall"
    );
    for rank_weight in RANK_WEIGHTS {
        for dictionary_weight in DICTIONARY_WEIGHTS {
            let mut hits = [0usize; 2];
            for row in &scored {
                let combined: Vec<f32> = row
                    .model
                    .iter()
                    .enumerate()
                    .map(|(index, score)| {
                        let dictionary = DICTIONARY_SOURCES.contains(&row.sources[index]);
                        score - rank_weight * index as f32
                            + if dictionary { dictionary_weight } else { 0.0 }
                    })
                    .collect();
                if row.texts[argmax(&combined)] == row.gold {
                    hits[usize::from(row.leader_is_dictionary)] += 1;
                }
            }
            let dictionary = hits[1] as f64 / dictionary_n.max(1) as f64;
            let decoded = hits[0] as f64 / decoded_n.max(1) as f64;
            let overall = (hits[0] + hits[1]) as f64 / scored.len().max(1) as f64;
            println!("{rank_weight:>6.2}{dictionary_weight:>7.2}  {dictionary:>12.3}{decoded:>10.3}{overall:>10.3}");
        }
    }
}

fn argmax(scores: &[f32]) -> usize {
    let mut best = 0;
    for (index, score) in scores.iter().enumerate() {
        if *score > scores[best] {
            best = index;
        }
    }
    best
}

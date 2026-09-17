//! Decodes pinyin into characters with the model, rather than reordering what the engine produced.
//!
//! Reranking can only pick among readings the engine already assembled, so a reading it never
//! proposes is out of reach no matter how confident the model is. Searching the syllables directly
//! removes that ceiling: every character the pinyin table allows for a syllable is a candidate, and
//! the model chooses among them using the characters already committed.
//!
//! usage: decode <model.safetensors> <rawdict_utf16_65105_freq.txt> <pinyin> [beam] [per-syllable]

use std::collections::HashMap;
use std::time::Instant;

use msime_sentence_model::SentenceModel;

/// Characters per syllable to consider. The table is ordered by corpus frequency, and the tail is
/// rare enough that admitting it costs search time without changing the answer.
const PER_SYLLABLE: usize = 12;
const BEAM: usize = 12;

fn read_table(path: &str) -> (HashMap<String, Vec<char>>, Vec<String>) {
    // The file is UTF-16LE: characters, frequency, a flag, then the reading.
    let bytes = std::fs::read(path).expect("read pinyin table");
    let units: Vec<u16> = bytes
        .chunks_exact(2)
        .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
        .collect();
    let text = String::from_utf16_lossy(&units);

    let mut rows: Vec<(String, char, f64)> = Vec::new();
    for line in text.lines() {
        let mut fields = line.split_whitespace();
        let (Some(word), Some(frequency), Some(_), Some(reading)) =
            (fields.next(), fields.next(), fields.next(), fields.next())
        else {
            continue;
        };
        let mut characters = word.chars();
        let (Some(character), None) = (characters.next(), characters.next()) else {
            continue;
        };
        let frequency: f64 = frequency.parse().unwrap_or(0.0);
        rows.push((reading.to_owned(), character, frequency));
    }

    let mut table: HashMap<String, Vec<(char, f64)>> = HashMap::new();
    for (reading, character, frequency) in rows {
        table
            .entry(reading)
            .or_default()
            .push((character, frequency));
    }
    let mut syllables: Vec<String> = table.keys().cloned().collect();
    // Longest first, so segmentation prefers `zhuang` over `zhu`.
    syllables.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));

    let ranked = table
        .into_iter()
        .map(|(reading, mut entries)| {
            entries.sort_by(|a, b| b.1.total_cmp(&a.1));
            let characters = entries.into_iter().map(|(ch, _)| ch).collect();
            (reading, characters)
        })
        .collect();
    (ranked, syllables)
}

/// Greedy longest-match segmentation. The engine has a better one; this only has to be good enough
/// to show whether searching the syllables reaches readings that reranking cannot.
fn segment(input: &str, syllables: &[String]) -> Option<Vec<String>> {
    let mut out = Vec::new();
    let mut rest = input;
    while !rest.is_empty() {
        let matched = syllables
            .iter()
            .find(|syllable| rest.starts_with(syllable.as_str()))?;
        out.push(matched.clone());
        rest = &rest[matched.len()..];
    }
    Some(out)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let model_path = args
        .next()
        .expect("usage: decode <model> <table> <pinyin> [beam] [per-syllable]");
    let table_path = args.next().expect("missing pinyin table");
    let input = args.next().expect("missing pinyin");
    let beam_width: usize = args.next().and_then(|v| v.parse().ok()).unwrap_or(BEAM);
    let per_syllable: usize = args
        .next()
        .and_then(|v| v.parse().ok())
        .unwrap_or(PER_SYLLABLE);

    let bytes = std::fs::read(&model_path).expect("read model");
    let model = SentenceModel::load(&bytes).expect("load model");
    let (table, syllables) = read_table(&table_path);

    let Some(parts) = segment(&input, &syllables) else {
        eprintln!("cannot segment {input}");
        std::process::exit(1);
    };
    println!("syllables: {}", parts.join(" "));

    let started = Instant::now();
    // Each beam is a reading so far and its summed log-probability.
    let mut beams: Vec<(String, f32)> = vec![(String::new(), 0.0)];
    for syllable in &parts {
        let Some(choices) = table.get(syllable) else {
            eprintln!("no characters for syllable {syllable}");
            std::process::exit(1);
        };
        let choices = &choices[..choices.len().min(per_syllable)];
        let mut next: Vec<(String, f32)> = Vec::new();
        for (text, score) in &beams {
            // One forward per beam gives the distribution every extension is scored against.
            let distribution = model.next_log_probabilities(text);
            for &character in choices {
                let Some(token) = model.token(character) else {
                    continue;
                };
                let mut extended = text.clone();
                extended.push(character);
                next.push((extended, score + distribution[token as usize]));
            }
        }
        next.sort_by(|a, b| b.1.total_cmp(&a.1));
        next.truncate(beam_width);
        beams = next;
    }
    let elapsed = started.elapsed();

    for (text, score) in beams.iter().take(8) {
        println!("  {:>9.3}  {text}", score / parts.len() as f32);
    }
    println!(
        "\n{} syllables, beam {beam_width}, {per_syllable} characters each: {elapsed:?}",
        parts.len()
    );
}

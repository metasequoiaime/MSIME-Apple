//! Measures pinyin-to-text conversion quality against the locked dictionary.
//!
//! Why this exists: neither the word lattice nor any later reranking can be shown to help or hurt
//! without a number to compare against, and the repository had none.
//!
//! Why it reports per source rather than top-1 alone: for three or more complete syllables the
//! Engine adds exactly one lattice path (`nbest = 1`) and then, when the Google-Pinyin fallback
//! produced a sentence, moves that fallback row to index 0 — quanpin/quanpin_dictionary.cpp, "Keep
//! one local Google-Pinyin sentence as the primary whole-sentence suggestion. The lattice is a
//! secondary source." Which source ends up at position 1 therefore depends on the input, and
//! whether a lattice change can move top-1 depends on that. `top1_source` and `gold_source` record
//! it per run instead of assuming either way.
//!
//! Learning is off and each case gets a fresh session, so one case cannot bias the next.

mod metrics;

use metrics::{Bucket, Observation, Report};
use msime_engine_bridge::{Command, Session};
use msime_input_runtime::{Action, Reranker, Runtime, SentenceModel};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

struct Case {
    id: String,
    input: String,
    gold: String,
    syllables: usize,
    tags: Vec<String>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut resources: Option<PathBuf> = None;
    let mut sets: Vec<PathBuf> = Vec::new();
    let mut limit: Option<usize> = None;
    let mut report_path: Option<PathBuf> = None;
    let mut baseline: Option<PathBuf> = None;
    let mut update = false;

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut index = 0;
    while index < args.len() {
        let take = |i: &mut usize| -> Result<String, String> {
            *i += 1;
            args.get(*i)
                .cloned()
                .ok_or_else(|| format!("{} needs a value", args[*i - 1]))
        };
        match args[index].as_str() {
            "--resources" => resources = Some(PathBuf::from(take(&mut index)?)),
            "--set" => sets.push(PathBuf::from(take(&mut index)?)),
            "--limit" => limit = Some(take(&mut index)?.parse()?),
            "--report" => report_path = Some(PathBuf::from(take(&mut index)?)),
            "--baseline" => baseline = Some(PathBuf::from(take(&mut index)?)),
            "--update-baseline" => update = true,
            other => return Err(format!("unknown option: {other}").into()),
        }
        index += 1;
    }
    let resources =
        resources.ok_or("usage: convert_eval --resources <verified-dir> --set <file.tsv> [...]")?;
    if sets.is_empty() {
        return Err("at least one --set is required".into());
    }

    let mut cases = Vec::new();
    for set in &sets {
        cases.extend(load(set)?);
    }
    if let Some(limit) = limit {
        // Deterministic subset: every nth case, so the sample keeps the set's length distribution
        // instead of taking a prefix that would be all short words.
        let stride = cases.len().div_ceil(limit.max(1));
        cases = cases.into_iter().step_by(stride.max(1)).collect();
    }
    eprintln!("{} cases from {} set(s)", cases.len(), sets.len());

    let state = tempfile::tempdir()?;
    let report = run(&resources, state.path(), &cases)?;
    let json = render(&report, &cases);

    if let Some(path) = &report_path {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(path, &json)?;
    }
    println!("{json}");

    if let Some(path) = baseline {
        if update {
            std::fs::write(&path, &json)?;
            eprintln!("baseline written: {}", path.display());
        } else if path.exists() {
            let previous = std::fs::read_to_string(&path)?;
            if previous.trim() != json.trim() {
                eprintln!(
                    "eval differs from {}; run with --update-baseline to accept",
                    path.display()
                );
                return Err("eval baseline mismatch".into());
            }
            eprintln!("eval: at baseline");
        }
    }
    Ok(())
}

fn load(path: &Path) -> Result<Vec<Case>, Box<dyn std::error::Error>> {
    let text = std::fs::read_to_string(path)?;
    let mut cases = Vec::new();
    for line in text.lines() {
        if line.starts_with('#') || line.is_empty() || line.starts_with("id\t") {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() < 4 {
            return Err(format!("{}: malformed row: {line}", path.display()).into());
        }
        cases.push(Case {
            id: fields[0].to_string(),
            input: fields[1].to_string(),
            gold: fields[2].to_string(),
            syllables: fields[3].parse()?,
            tags: fields
                .get(4)
                .map(|t| {
                    t.split(',')
                        .filter(|t| !t.is_empty())
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default(),
        });
    }
    Ok(cases)
}

fn run(
    resources: &Path,
    state: &Path,
    cases: &[Case],
) -> Result<Report, Box<dyn std::error::Error>> {
    // prepare_options is what actually makes a resource directory usable: it verifies the
    // generation, creates the user dictionaries and returns the four paths the Engine expects.
    // Passing the verified directory straight to EngineOptions yields a session with no
    // dictionaries attached, which produces an empty candidate list rather than an error.
    let generation = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../resources/desktop-dictionary.lock.json"),
    )?;
    let generation: serde_json::Value = serde_json::from_str(&generation)?;
    let generation = generation["source_commit"]
        .as_str()
        .ok_or("lock has no source_commit")?;
    let mut options = msime_engine_bridge::prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        state.join("user").to_str().ok_or("non-UTF-8 state path")?,
        state.join("cache").to_str().ok_or("non-UTF-8 cache path")?,
        generation,
    )?;
    options.scheme = 0;
    // Off so a case cannot promote its own answer for the cases that follow.
    options.learning = false;
    options.frequency_mode = "disabled".into();
    options.autocorrect_transposition = false;
    options.autocorrect_neighbor = false;
    options.fuzzy_pinyin_rules = 0;
    options.helpcode = false;
    options.show_helpcode = false;
    options.mixed_english = false;
    options.mixed_emoji = false;
    options.mixed_kaomoji = false;
    options.local_unicode = false;
    options.local_date_time = false;
    options.local_quick_phrase = false;
    options.local_emoji = false;
    options.local_kaomoji = false;
    options.local_super_jianpin = false;
    options.local_temporary_english = false;
    options.local_temporary_japanese = false;

    let engine = Session::new(&options)?;
    // page_size is capped at 9 by the runtime, but all_candidates() is not paginated.
    let mut runtime = Runtime::new(engine, 9)?;
    // Measuring the shipped path means measuring it with whatever the resource set contains. The
    // model is optional there, so its absence has to leave these numbers exactly as they were.
    let model_path = resources.join("sentence-model.safetensors");
    match std::fs::read(&model_path) {
        Ok(bytes) => {
            let model = SentenceModel::load(&bytes)?;
            eprintln!("reranking with {}", model_path.display());
            runtime.set_reranker(Some(Reranker::new(std::sync::Arc::new(model))));
        }
        Err(_) => eprintln!(
            "no model at {}, measuring the engine alone",
            model_path.display()
        ),
    }
    // dispatch() drops every action while unfocused, which yields an empty candidate list rather
    // than an error.
    runtime.focus(true)?;
    let mut report = Report::default();

    for case in cases {
        runtime.dispatch(Action::Command(Command::Cancel))?;
        for byte in case.input.bytes() {
            runtime.dispatch(Action::Character {
                value: byte,
                shift: false,
            })?;
        }
        let snapshot = runtime.all_candidates();
        let candidates: Vec<(String, u8)> = snapshot
            .candidates
            .iter()
            .map(|c| (c.text.clone(), c.source))
            .collect();
        report.observe(Observation {
            id: &case.id,
            input: &case.input,
            gold: &case.gold,
            tags: &case.tags,
            syllables: case.syllables,
            candidates: &candidates,
            keep_failure: report.failures.len() < 40,
        });
        runtime.dispatch(Action::Command(Command::Cancel))?;
    }
    Ok(report)
}

fn render(report: &Report, cases: &[Case]) -> String {
    let bucket = |b: &Bucket| {
        serde_json::json!({
            "cases": b.cases,
            "top1": round(Bucket::rate(b.top1, b.cases)),
            "top5": round(Bucket::rate(b.top5, b.cases)),
            "top9": round(Bucket::rate(b.top9, b.cases)),
            "found": round(Bucket::rate(b.found, b.cases)),
            "mrr": round(if b.cases == 0 { 0.0 } else { b.reciprocal_rank / b.cases as f64 }),
            "top1_char_prefix": round(if b.cases == 0 { 0.0 } else { b.top1_char_prefix / b.cases as f64 }),
        })
    };
    let by_syllables: BTreeMap<String, _> = report
        .by_syllables
        .iter()
        .map(|(k, v)| (k.to_string(), bucket(v)))
        .collect();
    let by_tag: BTreeMap<String, _> = report
        .by_tag
        .iter()
        .map(|(k, v)| (k.clone(), bucket(v)))
        .collect();

    let value = serde_json::json!({
        "cases": cases.len(),
        "overall": bucket(&report.overall),
        "by_syllables": by_syllables,
        "by_tag": by_tag,
        "gold_source": report.gold_source,
        "top1_source": report.top1_source,
        "sample_failures": report.failures.iter().take(40).map(|f| serde_json::json!({
            "id": f.id, "input": f.input, "gold": f.gold, "top1": f.got, "rank": f.rank,
        })).collect::<Vec<_>>(),
    });
    serde_json::to_string_pretty(&value).unwrap_or_default()
}

/// Three decimals: enough to see a real move, coarse enough that a one-case difference in a large
/// set does not rewrite the whole baseline file.
fn round(value: f64) -> f64 {
    (value * 1000.0).round() / 1000.0
}

//! Mine a licensed corpus for conversion failures, so the evaluation set can grow without anyone
//! writing sentences by hand.
//!
//! `sentences-v1.tsv` is 60 hand-written cases with no context. That size is its own ceiling —
//! `resources/eval/README.md` puts the 95% confidence half-width for a single arm at about 13
//! percentage points, which is wider than most changes worth making — and the missing context is a
//! second one: ranking 会议 above 回忆 is a judgement about what came before, and a set where
//! nothing came before cannot ask for it.
//!
//! Neither limit needs a labeller to lift. Real prose is its own gold answer: convert a sentence to
//! pinyin with the Engine's own table, type that pinyin back in, and any case where the top
//! candidate is not the sentence you started from is a failure with a known correct answer and a
//! real preceding sentence attached. The corpus supplies both for free.
//!
//! What this cannot decide is whether the original was the *only* natural reading of its pinyin.
//! `resources/eval/README.md` rules those out deliberately — "拼音本身就有两种同样自然写法的句子
//! 一律不收，评测集不能既诚实又有歧义" — and that is a judgement, not a filter. So this writes a
//! candidate file to be reviewed, not an evaluation set. Harvest, review, then commit.
//!
//! The corpus has to be one document per line with its punctuation intact, sentences in the order
//! they were written. That is a real constraint rather than a formality: the context column comes
//! from the sentence before, so a corpus that has had its punctuation stripped or its sentences
//! shuffled can only ever yield empty context. `chinese-ime-lm`'s `corpus/fetch.py` output does not
//! qualify — its `segment()` keeps runs of Han characters and clips them at a fixed width, which is
//! right for training a character model and wrong here. Feed it the punctuated source instead, and
//! do any archive or JSON unwrapping outside: keeping this reader plain text is what lets the
//! example stay free of corpus-format dependencies.
//!
//! Corpus attribution travels in the output header. C4's Chinese portion is ODC-BY and LCCC is MIT;
//! both require attribution to follow the text, and a file of harvested sentences is that text.
//!
//! usage: harvest_eval_set --resources <verified-dir> --corpus <file> --out <file.tsv>
//!                         [--limit N] [--min-chars N] [--max-chars N] [--attribution TEXT]

use msime_engine_bridge::{Command, Session};
use msime_input_runtime::{Action, Runtime};
use std::fmt::Write as _;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};

/// Sentence ends. Also the points a user would have committed at, which is what makes the text
/// before one of them a plausible context for the text after it.
const BREAKS: [char; 8] = ['。', '！', '？', '；', '…', '\n', '，', '、'];

/// Hard sentence ends only. Commas continue a thought, so they split context from case less
/// cleanly, but they still bound a unit a user types in one go.
const HARD_BREAKS: [char; 5] = ['。', '！', '？', '；', '…'];

struct Args {
    resources: PathBuf,
    corpus: PathBuf,
    out: PathBuf,
    limit: usize,
    min_chars: usize,
    max_chars: usize,
    attribution: String,
}

fn parse_args() -> Result<Args, Box<dyn std::error::Error>> {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let mut resources = None;
    let mut corpus = None;
    let mut out = None;
    let mut limit = 200usize;
    let mut min_chars = 4usize;
    let mut max_chars = 16usize;
    let mut attribution = String::new();
    let mut index = 0;
    while index < raw.len() {
        let take = |index: &mut usize| -> Result<String, String> {
            *index += 1;
            raw.get(*index)
                .cloned()
                .ok_or_else(|| format!("{} needs a value", raw[*index - 1]))
        };
        match raw[index].as_str() {
            "--resources" => resources = Some(PathBuf::from(take(&mut index)?)),
            "--corpus" => corpus = Some(PathBuf::from(take(&mut index)?)),
            "--out" => out = Some(PathBuf::from(take(&mut index)?)),
            "--limit" => limit = take(&mut index)?.parse()?,
            "--min-chars" => min_chars = take(&mut index)?.parse()?,
            "--max-chars" => max_chars = take(&mut index)?.parse()?,
            "--attribution" => attribution = take(&mut index)?,
            other => return Err(format!("unknown option: {other}").into()),
        }
        index += 1;
    }
    if min_chars < 2 || max_chars < min_chars {
        return Err("--min-chars must be at least 2 and no greater than --max-chars".into());
    }
    Ok(Args {
        resources: resources.ok_or("--resources is required")?,
        corpus: corpus.ok_or("--corpus is required")?,
        out: out.ok_or("--out is required")?,
        limit,
        min_chars,
        max_chars,
        attribution,
    })
}

/// Han characters only, and nothing the pinyin table cannot speak for.
///
/// Digits, Latin and punctuation all have their own input paths in the product and none of them is
/// what a conversion set measures. Rejecting the whole sentence rather than stripping them keeps
/// the pinyin and the characters in step, which every later check depends on.
fn is_plain_han(text: &str) -> bool {
    !text.is_empty() && text.chars().all(|c| ('\u{4e00}'..='\u{9fff}').contains(&c))
}

/// Split a corpus line into (context, sentence) pairs in order.
///
/// The context is the preceding hard-bounded sentence, or empty at the start of a line. A user who
/// has just committed one sentence and is typing the next is exactly this situation.
fn pairs(line: &str) -> Vec<(String, String)> {
    let mut sentences: Vec<String> = Vec::new();
    let mut current = String::new();
    for character in line.chars() {
        if BREAKS.contains(&character) {
            if !current.is_empty() {
                sentences.push(std::mem::take(&mut current));
            }
            if HARD_BREAKS.contains(&character) {
                continue;
            }
            continue;
        }
        current.push(character);
    }
    if !current.is_empty() {
        sentences.push(current);
    }
    let mut out = Vec::with_capacity(sentences.len());
    for (index, sentence) in sentences.iter().enumerate() {
        let context = if index == 0 {
            String::new()
        } else {
            sentences[index - 1].clone()
        };
        out.push((context, sentence.clone()));
    }
    out
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = parse_args()?;

    let state = tempfile::tempdir()?;
    let generation = std::fs::read_to_string(
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../resources/desktop-dictionary.lock.json"),
    )?;
    let generation: serde_json::Value = serde_json::from_str(&generation)?;
    let generation = generation["source_commit"]
        .as_str()
        .ok_or("lock has no source_commit")?;
    let mut options = msime_engine_bridge::prepare_options(
        args.resources.to_str().ok_or("non-UTF-8 resource path")?,
        state
            .path()
            .join("user")
            .to_str()
            .ok_or("non-UTF-8 state")?,
        state
            .path()
            .join("cache")
            .to_str()
            .ok_or("non-UTF-8 cache")?,
        generation,
    )?;
    // The same settings convert_eval measures under. Learning off above all: a harvested case must
    // not be made easier by the case before it.
    options.scheme = 0;
    options.learning = false;
    options.frequency_mode = "disabled".into();
    options.autocorrect_transposition = false;
    options.autocorrect_neighbor = false;
    options.fuzzy_pinyin_rules = 0;
    options.sentence_alternatives = true;

    let engine = Session::new(&options)?;
    let mut runtime = Runtime::new(engine, 9)?;
    runtime.focus(true)?;

    let mut rows = String::new();
    let mut kept = 0usize;
    let mut examined = 0usize;
    let mut rejected_pinyin = 0usize;
    let mut unreachable_gold = 0usize;
    // hanzi_to_pinyin walks the dictionary per call, so its cost dominates a corpus run and is
    // worth reporting rather than guessing at.
    let mut pinyin_calls = 0usize;
    let mut pinyin_time = std::time::Duration::ZERO;

    let file = std::fs::File::open(&args.corpus)?;
    'corpus: for line in BufReader::new(file).lines() {
        let line = line?;
        for (context, sentence) in pairs(&line) {
            if kept >= args.limit {
                break 'corpus;
            }
            let characters = sentence.chars().count();
            if characters < args.min_chars || characters > args.max_chars {
                continue;
            }
            if !is_plain_han(&sentence) {
                continue;
            }
            let started = std::time::Instant::now();
            // The Engine returns apostrophe-separated syllables; the evaluation format is the
            // unsegmented key a user actually types, and `normalize_full_pinyin` below re-cuts it
            // using the character count, so the separators are dropped rather than carried.
            let pinyin =
                msime_engine_bridge::hanzi_to_pinyin(&options, &sentence).replace('\'', "");
            pinyin_time += started.elapsed();
            pinyin_calls += 1;
            if pinyin_calls.is_multiple_of(500) {
                eprintln!(
                    "  {pinyin_calls} sentences converted, {kept} kept, \
                     hanzi_to_pinyin averaging {:.1}ms",
                    pinyin_time.as_secs_f64() * 1000.0 / pinyin_calls as f64
                );
            }
            // The table has to speak for every character, and the syllables have to cut the same
            // way the decoder will cut them. Anything else measures the pinyin table, not the
            // conversion.
            if pinyin.is_empty()
                || !pinyin.bytes().all(|b| b.is_ascii_lowercase())
                || msime_engine_bridge::normalize_full_pinyin(&pinyin, characters).is_empty()
            {
                rejected_pinyin += 1;
                continue;
            }
            examined += 1;

            runtime.dispatch(Action::Command(Command::Cancel))?;
            runtime.seed_context(&context);
            for byte in pinyin.bytes() {
                runtime.dispatch(Action::Character {
                    value: byte,
                    shift: false,
                })?;
            }
            let snapshot = runtime.all_candidates();
            let top = snapshot
                .candidates
                .first()
                .map(|candidate| candidate.text.as_str())
                .unwrap_or("");
            let matched = top == sentence;
            runtime.dispatch(Action::Command(Command::Cancel))?;
            if matched {
                continue;
            }

            // Only keep cases whose gold answer is somewhere in the list.
            //
            // `hanzi_to_pinyin` is not always right about polyphones — 可能 comes back as
            // `ge'neng` — and a wrong key cannot decode to the sentence it came from. "Gold is
            // absent" therefore does not distinguish a decoder failure from a mis-keyed sentence,
            // and harvesting those would fill the set with cases that are unreachable by
            // construction. Requiring the gold to appear proves the key was right and leaves a
            // failure that ranking can actually be asked about.
            let Some(position) = snapshot
                .candidates
                .iter()
                .position(|candidate| candidate.text == sentence)
            else {
                unreachable_gold += 1;
                continue;
            };
            let rank = position + 1;
            kept += 1;
            writeln!(
                rows,
                "h-{kept:05}\t{pinyin}\t{sentence}\t{characters}\tharvested\t{context}\t{top}\t{rank}"
            )?;
        }
    }

    let mut out = String::new();
    writeln!(out, "# 从语料收割的转换失败用例，未经评审。")?;
    writeln!(out, "#")?;
    writeln!(
        out,
        "# 金标准是原文本身：句子经 Engine 的拼音表转成拼音再解码，首选与原文不同即收录。"
    )?;
    writeln!(
        out,
        "# 这里**没有**判断过原文是否是该拼音串唯一自然的写法，而评测集不收两可的句子。"
    )?;
    writeln!(
        out,
        "# 因此这是待评审的候选，不是评测集；评审通过的行才并入 sentences-v*.tsv。"
    )?;
    writeln!(out, "#")?;
    writeln!(
        out,
        "# 列：id / 拼音 / 金标准 / 字数 / 标签 / 上文 / 当前首选 / 金标准排名"
    )?;
    if !args.attribution.is_empty() {
        writeln!(out, "#")?;
        writeln!(out, "# 语料署名：{}", args.attribution)?;
    }
    out.push_str(&rows);
    if let Some(parent) = args.out.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(&args.out, out)?;

    eprintln!(
        "examined {examined} usable sentences, rejected {rejected_pinyin} the pinyin table could not \
         round-trip, dropped {unreachable_gold} whose gold never appeared, kept {kept} failures \
         ({pinyin_calls} hanzi_to_pinyin calls averaging {:.1}ms) -> {}",
        pinyin_time.as_secs_f64() * 1000.0 / pinyin_calls.max(1) as f64,
        args.out.display()
    );
    Ok(())
}

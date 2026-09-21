//! Which seat each kind of candidate takes when several arrive at once.
//!
//! The reference writes the arrangement out in `candidate_selection_policy.h`:
//!
//! ```text
//! no cloud:    Chinese, English, AI, emoji, kaomoji
//! cloud:       Chinese, cloud, AI, English, emoji, kaomoji
//! cloud only:  Chinese, cloud, English, emoji, kaomoji
//! base:        Chinese, English, emoji, kaomoji
//! ```
//!
//! The surprising line is the second: English moves behind AI once a cloud result is present. That
//! is a rule about four kinds of candidate at once, so it needs a real dictionary to produce the
//! English, emoji and kaomoji ones - the neighbouring `mixed_ordering_dictionary` probe pins emoji
//! and kaomoji against each other, and this one adds the online seats.
//!
//! usage: mixed_slots <verified-dictionary-directory>

use msime_engine_bridge::{prepare_options, Session};
use msime_input_runtime::{Action, Runtime};

fn texts(runtime: &Runtime<Session>) -> Vec<String> {
    runtime
        .view()
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect()
}

fn seat(list: &[String], text: &str) -> Option<usize> {
    list.iter().position(|value| value == text)
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: mixed_slots <verified-dictionary-directory>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let mut options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "mixed-slot-probe",
    )?;
    options.mixed_english = true;
    options.english_minimum_prefix = 2;
    options.mixed_emoji = true;
    options.mixed_kaomoji = true;

    let compose =
        |runtime: &mut Runtime<Session>, input: &str| -> Result<(), Box<dyn std::error::Error>> {
            for byte in input.bytes() {
                runtime.dispatch(Action::Character {
                    value: byte,
                    shift: false,
                })?;
            }
            Ok(())
        };

    // `ni` produces all four kinds at once - a Chinese word, the English `ni`, an emoji and a
    // kaomoji - and is eligible for both online sources, which no English-looking query is.
    let input = "ni";
    let cloud = "合成云候选";
    let ai = "合成 AI 候选";

    let arrangement =
        |cloud_first: bool, ai_too: bool| -> Result<Vec<String>, Box<dyn std::error::Error>> {
            let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
            runtime.focus(true)?;
            compose(&mut runtime, input)?;
            if cloud_first || ai_too {
                let query = runtime
                    .online_query()?
                    .ok_or("the composition is not online-eligible")?;
                if cloud_first {
                    assert!(
                        runtime.apply_online_candidate(&query, cloud, 0)?,
                        "cloud refused"
                    );
                }
                if ai_too {
                    assert!(runtime.apply_online_candidate(&query, ai, 1)?, "AI refused");
                }
            }
            Ok(texts(&runtime))
        };

    // base: Chinese, English, emoji, kaomoji.
    let base = arrangement(false, false)?;
    let english = base
        .get(1)
        .cloned()
        .ok_or_else(|| format!("no second candidate in {base:?}"))?;
    assert!(
        english.is_ascii(),
        "the second seat should be the English candidate: {base:?}"
    );
    let emoji = base
        .get(2)
        .cloned()
        .ok_or_else(|| format!("no third candidate in {base:?}"))?;
    let kaomoji = base
        .get(3)
        .cloned()
        .ok_or_else(|| format!("no fourth candidate in {base:?}"))?;
    assert!(
        !emoji.is_ascii() && !kaomoji.is_ascii(),
        "base arrangement: {base:?}"
    );

    let ordered = |list: &[String], wanted: &[&str]| {
        let seats: Vec<Option<usize>> = wanted.iter().map(|text| seat(list, text)).collect();
        assert!(
            seats.iter().all(Option::is_some),
            "missing {wanted:?} from {list:?}"
        );
        let seats: Vec<usize> = seats.into_iter().flatten().collect();
        assert!(
            seats.windows(2).all(|pair| pair[0] < pair[1]),
            "expected {wanted:?} in that order, got {list:?}"
        );
    };

    // cloud only: Chinese, cloud, English, emoji, kaomoji.
    let with_cloud = arrangement(true, false)?;
    assert_eq!(
        seat(&with_cloud, cloud),
        Some(1),
        "cloud takes the second seat: {with_cloud:?}"
    );
    ordered(&with_cloud, &[cloud, &english, &emoji, &kaomoji]);

    // no cloud: Chinese, English, AI, emoji, kaomoji - the AI result sits behind English.
    let with_ai = arrangement(false, true)?;
    ordered(&with_ai, &[&english, ai, &emoji, &kaomoji]);

    // cloud and AI: Chinese, cloud, AI, English, emoji, kaomoji - English moves behind both.
    let with_both = arrangement(true, true)?;
    assert_eq!(
        seat(&with_both, cloud),
        Some(1),
        "cloud keeps the second seat: {with_both:?}"
    );
    ordered(&with_both, &[cloud, ai, &english, &emoji, &kaomoji]);

    println!("mixed slots: all four arrangements match the reference's table - English leads without a cloud result and follows the AI one with it");
    Ok(())
}

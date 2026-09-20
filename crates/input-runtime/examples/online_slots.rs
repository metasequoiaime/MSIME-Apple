//! Where a cloud suggestion and an AI suggestion land among the candidates.
//!
//! The reference states both positions: a cloud result that is not already in the local list is
//! inserted as the second item on the first page, and an AI result as the third. The placement is
//! the Engine's, and it cannot be seen without a real candidate list to insert into - which is why
//! this is an example beside the other dictionary probes rather than a CTest.
//!
//! No network: the provider results are handed to the runtime directly, which is the same entry
//! point a real provider's callback uses.
//!
//! usage: online_slots <verified-dictionary-directory>

use msime_engine_bridge::{prepare_options, Session};
use msime_input_runtime::{Action, Runtime};

fn candidates(runtime: &Runtime<Session>) -> Vec<String> {
    runtime
        .view()
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: online_slots <verified-dictionary-directory>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let options = prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "online-slot-probe",
    )?;

    let compose = |runtime: &mut Runtime<Session>| -> Result<(), Box<dyn std::error::Error>> {
        for byte in b"nihao" {
            runtime.dispatch(Action::Character {
                value: *byte,
                shift: false,
            })?;
        }
        Ok(())
    };

    // A cloud suggestion the local dictionary does not have takes the second seat.
    let mut runtime = Runtime::new(Session::new(&options)?, 9)?;
    runtime.focus(true)?;
    compose(&mut runtime)?;
    let local = candidates(&runtime);
    let query = runtime
        .online_query()?
        .ok_or("the composition is not online-eligible")?;
    assert!(
        query.cloud_eligible,
        "a five-letter pinyin query should be cloud eligible"
    );
    let cloud = "合成云候选";
    assert!(!local.contains(&cloud.to_string()));
    assert!(runtime.apply_online_candidate(&query, cloud, 0)?);
    let with_cloud = candidates(&runtime);
    assert_eq!(
        with_cloud.get(1).map(String::as_str),
        Some(cloud),
        "cloud landed at {:?}",
        with_cloud.iter().position(|text| text == cloud)
    );
    assert_eq!(
        with_cloud.first(),
        local.first(),
        "the local first choice must keep its seat"
    );

    // An AI suggestion takes the third, behind the cloud one.
    let ai = "合成 AI 候选";
    assert!(runtime.apply_online_candidate(&query, ai, 1)?);
    let with_both = candidates(&runtime);
    assert_eq!(with_both.get(1).map(String::as_str), Some(cloud));
    assert_eq!(
        with_both.get(2).map(String::as_str),
        Some(ai),
        "AI landed at {:?}",
        with_both.iter().position(|text| text == ai)
    );

    // On its own it moves up rather than holding the third seat. The README numbers the seats -
    // 「插入首页第三项」 - but the arrangement in `candidate_selection_policy.h` packs them: one
    // local, then cloud, then English, then AI, each only when it exists. This query has no cloud
    // result and no English candidate, so the AI one is second. The implementation is what the user
    // gets, so it is what this pins.
    let mut alone = Runtime::new(Session::new(&options)?, 9)?;
    alone.focus(true)?;
    compose(&mut alone)?;
    let query = alone
        .online_query()?
        .ok_or("the composition is not online-eligible")?;
    assert!(alone.apply_online_candidate(&query, ai, 1)?);
    let ai_only = candidates(&alone);
    assert_eq!(
        ai_only.get(1).map(String::as_str),
        Some(ai),
        "AI alone landed in {ai_only:?}"
    );
    assert_eq!(
        ai_only.first(),
        local.first(),
        "the local first choice keeps its seat"
    );

    // A cloud result the local list already has is not inserted twice.
    let mut duplicate = Runtime::new(Session::new(&options)?, 9)?;
    duplicate.focus(true)?;
    compose(&mut duplicate)?;
    let query = duplicate
        .online_query()?
        .ok_or("the composition is not online-eligible")?;
    let existing = candidates(&duplicate)[0].clone();
    duplicate.apply_online_candidate(&query, &existing, 0)?;
    let after = candidates(&duplicate);
    assert_eq!(
        after.iter().filter(|text| **text == existing).count(),
        1,
        "the existing candidate was duplicated: {after:?}"
    );

    println!("online slots: cloud takes the second seat, AI follows it, an AI result on its own moves up, and a duplicate of a local candidate is not inserted");
    Ok(())
}

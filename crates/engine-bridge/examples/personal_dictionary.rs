//! Exercise Engine-managed edits on an isolated copy, never a live user's dictionary.
use msime_engine_bridge::{
    dictionary_edit, dictionary_entries, prepare_options, DictionaryEntry, DictionaryKind, Session,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: personal_dictionary <verified-resources>")?,
    )?;
    let temporary = tempfile::tempdir()?;
    let options = prepare_options(
        resources.to_str().unwrap(),
        temporary.path().join("user").to_str().unwrap(),
        temporary.path().join("cache").to_str().unwrap(),
        "personal-fixture",
    )?;
    let entries = [
        DictionaryEntry {
            kind: DictionaryKind::Pinyin,
            key: "ce'shi'ci".into(),
            value: "测试词".into(),
            weight: 12345,
        },
        DictionaryEntry {
            kind: DictionaryKind::Wubi,
            key: "aaaa".into(),
            value: "测试".into(),
            weight: 12345,
        },
        DictionaryEntry {
            kind: DictionaryKind::QuickPhrase,
            key: "fixture".into(),
            value: "测试短语".into(),
            weight: 12345,
        },
        DictionaryEntry {
            kind: DictionaryKind::English,
            key: "fixture".into(),
            value: "fixture".into(),
            weight: 12345,
        },
    ];
    assert!(dictionary_entries(&options, 0, 100)?.entries.is_empty());
    for (index, entry) in entries.iter().enumerate() {
        let request = format!("fixture-add-{index}");
        dictionary_edit(&options, None, Some(entry), &request)?;
        dictionary_edit(&options, None, Some(entry), &request)?;
    }
    let first = dictionary_entries(&options, 0, 2)?;
    let second = dictionary_entries(&options, 2, 2)?;
    assert!(first.has_more && !second.has_more);
    let mut listed = first.entries;
    listed.extend(second.entries);
    assert_eq!(
        listed,
        [
            entries[3].clone(),
            entries[0].clone(),
            entries[2].clone(),
            entries[1].clone()
        ]
    );
    assert!(dictionary_entries(&options, 0, 0).is_err());
    assert!(dictionary_entries(&options, 0, 1001).is_err());
    assert!(dictionary_entries(&options, 1_000_001, 1).is_err());
    let previous = &entries[2];
    let mut replacement = previous.clone();
    replacement.value = "测试替换".into();
    replacement.weight = 67890;
    assert!(dictionary_edit(&options, None, Some(&replacement), "fixture-add-2").is_err());
    dictionary_edit(
        &options,
        Some(previous),
        Some(&replacement),
        "fixture-replace",
    )?;
    dictionary_edit(
        &options,
        Some(previous),
        Some(&replacement),
        "fixture-replace",
    )?;
    assert!(dictionary_edit(&options, Some(previous), None, "fixture-stale").is_err());
    let mut invalid = replacement.clone();
    invalid.key = "!".into();
    assert!(dictionary_edit(
        &options,
        Some(&replacement),
        Some(&invalid),
        "fixture-invalid"
    )
    .is_err());
    assert_eq!(
        dictionary_entries(&options, 2, 1)?.entries,
        [replacement.clone()]
    );
    // No session is alive during edits. Reopen after each write to invalidate Engine caches.
    {
        let mut session = Session::new(&options)?;
        session.character(b'K', true)?;
        for byte in b"fixture" {
            session.character(*byte, false)?;
        }
        let index = session
            .snapshot()?
            .candidates
            .iter()
            .position(|word| word == &replacement.value)
            .ok_or("edited phrase not visible")?;
        let result = session.select(index)?;
        assert!(
            result.has_commit && result.commit == replacement.value && result.diagnostic.is_empty()
        );
    }
    dictionary_edit(&options, Some(&replacement), None, "fixture-remove")?;
    dictionary_edit(&options, Some(&replacement), None, "fixture-remove")?;
    assert!(!dictionary_entries(&options, 0, 100)?
        .entries
        .contains(&replacement));
    let mut session = Session::new(&options)?;
    session.character(b'K', true)?;
    for byte in b"fixture" {
        session.character(*byte, false)?;
    }
    assert!(!session.snapshot()?.candidates.contains(&replacement.value));
    println!("four dictionary kinds, pagination, idempotency, stale/invalid rejection and quick-phrase visibility passed");
    Ok(())
}

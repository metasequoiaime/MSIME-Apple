use super::*;
use crate::{dictionary_state_revision, Session};
use rusqlite::Connection;
use std::path::Path;

fn resources(root: &Path) -> EngineOptions {
    let options = crate::tests::options(root);
    // Synthetic resource schema follows pinned Engine test_dictionary_state.cpp.
    Connection::open(Path::new(&options.resources).join("msime.db"))
        .unwrap()
        .execute_batch(
            "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);
             INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',100),('ni''hao','nh','拟好',80);
             CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);
             CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER);
             CREATE INDEX idx_quick_parases_key_weight ON quick_parases(key,weight DESC);",
        )
        .unwrap();
    Connection::open(Path::new(&options.resources).join("english.db"))
        .unwrap()
        .execute_batch(
            "CREATE TABLE english_words(word TEXT COLLATE BINARY NOT NULL,display TEXT NOT NULL,
             weight INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(word,display)) WITHOUT ROWID;
             CREATE TABLE en_zh_glosses(english TEXT COLLATE BINARY PRIMARY KEY,chinese_gloss TEXT NOT NULL) WITHOUT ROWID;
             CREATE TABLE zh_en_glosses(chinese TEXT COLLATE BINARY PRIMARY KEY,english_gloss TEXT NOT NULL) WITHOUT ROWID;
             PRAGMA user_version=3;",
        )
        .unwrap();
    options
}

#[test]
fn helpcode_display_toggle_keeps_candidates_and_filtering_enabled() {
    let root = tempfile::tempdir().unwrap();
    let mut options = resources(root.path());
    let helpcodes = Path::new(&options.resources).join("helpcodes");
    std::fs::create_dir_all(&helpcodes).unwrap();
    std::fs::write(
        helpcodes.join("zrm_helpcode_big_unique.txt"),
        "你=ab\n好=cd\n拟=ef\n",
    )
    .unwrap();
    options.helpcode = true;
    options = stage(&options, &root.path().join("display-fixture"), Vec::new()).unwrap();
    let mut candidates = None;
    for visible in [true, false, true] {
        options.show_helpcode = visible;
        let mut session = Session::new(&options).unwrap();
        for ch in b"nihao" {
            session.character(*ch, false).unwrap();
        }
        let view = session.snapshot().unwrap();
        assert!(!view.candidates.is_empty());
        if let Some(previous) = &candidates {
            assert_eq!(&view.candidates, previous);
        }
        candidates = Some(view.candidates.clone());
        assert_eq!(
            view.candidate_annotations
                .iter()
                .any(|value| !value.is_empty()),
            visible
        );
        assert!(session.character(b'A', true).unwrap().handled);
    }
}

#[test]
fn hiding_helpcode_restores_correction_annotations() {
    let root = tempfile::tempdir().unwrap();
    let mut options = resources(root.path());
    Connection::open(Path::new(&options.resources).join("msime.db"))
        .unwrap()
        .execute_batch(
            "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER);
             INSERT INTO tbl_2_s VALUES('shang''hao','sh','上好',100);",
        )
        .unwrap();
    let helpcodes = Path::new(&options.resources).join("helpcodes");
    std::fs::create_dir_all(&helpcodes).unwrap();
    std::fs::write(
        helpcodes.join("zrm_helpcode_big_unique.txt"),
        "上=ab\n好=cd\n",
    )
    .unwrap();
    options.helpcode = true;
    options = stage(
        &options,
        &root.path().join("correction-fixture"),
        Vec::new(),
    )
    .unwrap();
    for visible in [true, false, true] {
        options.show_helpcode = visible;
        let mut session = Session::new(&options).unwrap();
        // Same transposition used by the pinned Engine's pinyin correction tests.
        for ch in b"sahnghao" {
            session.character(*ch, false).unwrap();
        }
        let view = session.snapshot().unwrap();
        let index = view
            .candidates
            .iter()
            .position(|text| text == "上好")
            .unwrap();
        let annotation = &view.candidate_annotations[index];
        if visible {
            assert!(!annotation.is_empty());
            assert_ne!(annotation, "sahnghao");
        } else {
            assert_eq!(annotation, "sahnghao");
        }
    }
}

#[test]
fn wubi_candidate_codes_stay_aligned_with_candidates() {
    let root = tempfile::tempdir().unwrap();
    let options = resources(root.path());
    Connection::open(Path::new(&options.dictionaries).join("msime.db"))
        .unwrap()
        .execute_batch(
            "CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);
             INSERT INTO wubi86 VALUES('a','工',100),('ab','干',90),('abce','平',80);",
        )
        .unwrap();
    let mut options = options;
    options.scheme = 2;
    let mut session = Session::new(&options).unwrap();
    session.character(b'a', false).unwrap();
    let view = session.snapshot().unwrap();
    assert_eq!(view.candidate_codes.len(), view.candidates.len());
    let work = view
        .candidates
        .iter()
        .position(|word| word == "工")
        .unwrap();
    assert_eq!(view.candidate_codes[work], "a");
    let dry = view
        .candidates
        .iter()
        .position(|word| word == "干")
        .unwrap();
    assert_eq!(view.candidate_codes[dry], "ab");
}

#[test]
fn correction_types_are_independent_for_real_candidates() {
    let root = tempfile::tempdir().unwrap();
    let mut options = resources(root.path());
    Connection::open(Path::new(&options.resources).join("msime.db"))
        .unwrap()
        .execute_batch(
            "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER);
             INSERT INTO tbl_2_s VALUES('shang''hao','sh','上好',100);",
        )
        .unwrap();
    options = stage(&options, &root.path().join("correction-matrix"), Vec::new()).unwrap();
    for transposition in [false, true] {
        for neighbor in [false, true] {
            options.autocorrect_transposition = transposition;
            options.autocorrect_neighbor = neighbor;
            for (input, expected) in [
                // Use a non-alias transposition: legacy sahng -> shang remains
                // available independently of both correction switches.
                ("shnaghao", transposition),
                ("sahnghao", true),
                ("shabghao", neighbor),
                ("shanghao", true),
            ] {
                let mut session = Session::new(&options).unwrap();
                for ch in input.bytes() {
                    session.character(ch, false).unwrap();
                }
                let view = session.snapshot().unwrap();
                let candidate = view.candidates.iter().position(|text| text == "上好");
                assert_eq!(
                    candidate.is_some(),
                    expected,
                    "{input}: transposition={transposition}, neighbor={neighbor}"
                );
                assert_eq!(view.editing_text, input);
                if expected && input != "shanghao" {
                    assert_eq!(view.candidate_annotations[candidate.unwrap()], input);
                    assert_eq!(view.preedit, input);
                }
            }
        }
    }
}

fn records() -> Vec<DictionaryStateRecord> {
    use DictionaryStateRecord::*;
    vec![
        Entry {
            kind: DictionaryKind::Pinyin,
            key: "ni'hao".into(),
            value: "你好".into(),
            weight: 0,
            display: "".into(),
            deleted: true,
            user_inserted: true,
        },
        Entry {
            kind: DictionaryKind::Pinyin,
            key: "ni'hao".into(),
            value: "拟好".into(),
            weight: 200,
            display: "".into(),
            deleted: false,
            user_inserted: false,
        },
        Entry {
            kind: DictionaryKind::Pinyin,
            key: "ni'hao".into(),
            value: "拟蒿".into(),
            weight: 150,
            display: "".into(),
            deleted: false,
            user_inserted: true,
        },
        Entry {
            kind: DictionaryKind::Wubi,
            key: "fixture".into(),
            value: "合成五笔".into(),
            weight: 100,
            display: "".into(),
            deleted: false,
            user_inserted: true,
        },
        Entry {
            kind: DictionaryKind::QuickPhrase,
            key: "fixture".into(),
            value: "合成短语".into(),
            weight: 100,
            display: "".into(),
            deleted: false,
            user_inserted: true,
        },
        Entry {
            kind: DictionaryKind::English,
            key: "cloudfixture".into(),
            value: "Cloudfixture".into(),
            weight: 100,
            display: "Cloudfixture".into(),
            deleted: false,
            user_inserted: true,
        },
        Position {
            context: "ni'hao".into(),
            key: "ni'hao".into(),
            value: "拟蒿".into(),
            position: 1,
        },
        Selection {
            context: "ni'hao".into(),
            key: "ni'hao".into(),
            value: "拟好".into(),
            count: 7,
        },
    ]
}

fn stage(
    options: &EngineOptions,
    generation: &Path,
    records: Vec<DictionaryStateRecord>,
) -> Result<EngineOptions, cxx::Exception> {
    stage_dictionary_state(
        options,
        generation.to_str().unwrap(),
        "fixture",
        100,
        records.into_iter().map(Ok),
    )
}

fn candidates(options: EngineOptions) -> Vec<String> {
    let mut session = Session::new(&options).unwrap();
    for ch in b"nihao" {
        session.character(*ch, false).unwrap();
    }
    session.snapshot().unwrap().candidates
}

#[test]
fn complete_state_rebuild_changes_real_engine_candidates_without_touching_source() {
    let root = tempfile::tempdir().unwrap();
    let options = resources(root.path());
    let original = std::fs::read(Path::new(&options.resources).join("msime.db")).unwrap();
    let active_revision = dictionary_state_revision(&options).unwrap();
    let restored = stage(&options, &root.path().join("restored"), records()).unwrap();
    assert_eq!(restored.learning, options.learning);
    assert_eq!(restored.frequency_mode, options.frequency_mode);
    assert_eq!(restored.shuangpin_profile, options.shuangpin_profile);
    assert_eq!(restored.resources, options.resources);
    assert_ne!(restored.user_data, options.user_data);
    assert_ne!(restored.cache, options.cache);
    assert_ne!(restored.dictionaries, options.dictionaries);
    let journal = Connection::open(Path::new(&restored.user_data).join("msime_user.db")).unwrap();
    let entries: i64 = journal
        .query_row("SELECT count(*) FROM user_dictionary_operations", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(entries, 6);
    let deletion: (String, i64) = journal
        .query_row(
            "SELECT operation,user_inserted FROM user_dictionary_operations WHERE value='你好'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(deletion, ("delete".into(), 1));
    let count: i64 = journal
        .query_row(
            "SELECT selection_count FROM candidate_selection_state",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(count, 7);
    let main = Connection::open(Path::new(&restored.dictionaries).join("msime.db")).unwrap();
    for (table, value) in [("wubi86", "合成五笔"), ("quick_parases", "合成短语")] {
        let actual: String = main
            .query_row(&format!("SELECT value FROM {table}"), [], |r| r.get(0))
            .unwrap();
        assert_eq!(actual, value);
    }
    let english = Connection::open(Path::new(&restored.dictionaries).join("english.db")).unwrap();
    let word: (String, String, i64) = english
        .query_row("SELECT word,display,weight FROM english_words", [], |r| {
            Ok((r.get(0)?, r.get(1)?, r.get(2)?))
        })
        .unwrap();
    assert_eq!(word, ("cloudfixture".into(), "Cloudfixture".into(), 100));
    let result = candidates(restored.clone());
    assert_eq!(result[0], "拟蒿");
    assert!(!result.contains(&"你好".into()));
    assert_eq!(
        dictionary_state_revision(&options).unwrap(),
        active_revision
    );
    assert_eq!(
        std::fs::read(Path::new(&options.resources).join("msime.db")).unwrap(),
        original
    );
    // Empty replacement starts from immutable resources, never the restored overlay.
    let empty = stage(&restored, &root.path().join("empty"), vec![]).unwrap();
    assert_eq!(candidates(empty)[0], "你好");
}

#[test]
fn rejected_records_and_transport_failures_remove_only_new_generation() {
    let root = tempfile::tempdir().unwrap();
    let options = resources(root.path());
    let target = root.path().join("rejected");
    let mut duplicate = records();
    duplicate.push(duplicate[0].clone());
    let mut conflicting_slot = records();
    conflicting_slot.push(DictionaryStateRecord::Position {
        context: "ni'hao".into(),
        key: "ni'hao".into(),
        value: "拟好".into(),
        position: 1,
    });
    for invalid in [
        duplicate,
        conflicting_slot,
        vec![DictionaryStateRecord::Position {
            context: "ctx".into(),
            key: "key".into(),
            value: "value".into(),
            position: i64::MAX,
        }],
        vec![DictionaryStateRecord::Selection {
            context: "ctx".into(),
            key: "key".into(),
            value: "value".into(),
            count: -1,
        }],
        vec![DictionaryStateRecord::Selection {
            context: "ctx\0bad".into(),
            key: "key".into(),
            value: "value".into(),
            count: 1,
        }],
    ] {
        assert!(stage(&options, &target, invalid).is_err());
        assert!(!target.exists());
    }
    for maximum in [0, 1] {
        assert!(stage_dictionary_state(
            &options,
            target.to_str().unwrap(),
            "fixture",
            maximum,
            records().into_iter().map(Ok)
        )
        .is_err());
        assert!(!target.exists());
    }
    // A checksum/truncation error after the last record is not successful EOF.
    let stream = records()
        .into_iter()
        .map(Ok)
        .chain(std::iter::once(Err(SnapshotReadError)));
    assert!(
        stage_dictionary_state(&options, target.to_str().unwrap(), "fixture", 8, stream).is_err()
    );
    assert!(!target.exists());
    assert!(stage_dictionary_state(
        &options,
        target.to_str().unwrap(),
        "../escape",
        8,
        records().into_iter().map(Ok)
    )
    .is_err());
    assert!(!target.exists());
    let existing = stage(&options, &target, records()).unwrap();
    let revision = dictionary_state_revision(&existing).unwrap();
    assert!(stage(&options, &target, vec![]).is_err());
    assert_eq!(dictionary_state_revision(&existing).unwrap(), revision);
    let inside_resources = Path::new(&options.resources).join("forbidden");
    assert!(stage(&options, &inside_resources, records()).is_err());
    assert!(!inside_resources.exists());
}

#[test]
fn stream_is_lazy_and_rebuild_failure_cleans_staging() {
    use std::{cell::Cell, rc::Rc};
    let root = tempfile::tempdir().unwrap();
    let options = resources(root.path());
    let target = root.path().join("limited");
    let consumed = Rc::new(Cell::new(0));
    let counter = consumed.clone();
    let stream = (0..100_000).map(move |index| {
        counter.set(counter.get() + 1);
        Ok(DictionaryStateRecord::Entry {
            kind: DictionaryKind::QuickPhrase,
            key: format!("fixture{index}"),
            value: "合成短语".into(),
            weight: 100,
            display: "".into(),
            deleted: false,
            user_inserted: true,
        })
    });
    assert!(
        stage_dictionary_state(&options, target.to_str().unwrap(), "fixture", 2, stream).is_err()
    );
    assert_eq!(consumed.get(), 3);
    assert!(!target.exists());

    // All records are valid, but rebuilding fails after the stream is consumed.
    let missing = root.path().join("missing-resources");
    std::fs::create_dir(&missing).unwrap();
    let mut unavailable = options;
    unavailable.resources = missing.to_str().unwrap().into();
    assert!(stage(&unavailable, &target, records()).is_err());
    assert!(!target.exists());
    assert!(missing.is_dir());
}

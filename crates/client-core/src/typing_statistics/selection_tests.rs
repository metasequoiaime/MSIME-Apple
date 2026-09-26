//! Unit tests for the parent module, in their own file because the module
//! is large enough that mixing them with the implementation obscured both.
//! Same `mod selection_tests` as before, so `use super::*` still names the parent.

use super::*;

fn store() -> (tempfile::TempDir, TypingStatisticsStore) {
    let directory = tempfile::tempdir().expect("tempdir");
    let store = TypingStatisticsStore::new(directory.path());
    // These tests are about counting, not about the default. Statistics ship off.
    store.set_enabled(true).expect("enable");
    (directory, store)
}

#[test]
fn counts_by_position_and_folds_the_tail() {
    let (_directory, store) = store();
    for position in [1, 1, 1, 2, 9, 10, 40] {
        store.record_selection(position).expect("record");
    }
    let value = store.load().expect("load");
    assert_eq!(value.selections.ranks[0], 3);
    assert_eq!(value.selections.ranks[1], 1);
    assert_eq!(value.selections.ranks[8], 1);
    // Tenth and fortieth are both past a page and are not told apart.
    assert_eq!(value.selections.beyond, 2);
    assert_eq!(value.selections.total(), 7);
}

#[test]
fn rejects_a_zero_position() {
    let (_directory, store) = store();
    assert!(matches!(
        store.record_selection(0),
        Err(TypingStatisticsError::InvalidPosition)
    ));
}

#[test]
fn the_shared_switch_and_reset_cover_it() {
    let (_directory, store) = store();
    store.record_selection(1).expect("record");
    store.set_enabled(false).expect("disable");
    store.record_selection(1).expect("record while off");
    assert_eq!(store.load().expect("load").selections.total(), 1);

    store.set_enabled(true).expect("enable");
    store.record_selection(3).expect("record");
    let value = store.reset().expect("reset");
    assert_eq!(value.selections.total(), 0);
}

#[test]
fn a_file_written_before_this_existed_still_loads() {
    let (directory, store) = store();
    std::fs::write(
        directory.path().join("typing-statistics.json"),
        br#"{"enabled":true,"total":5,"days":{},"detail":{},"dailyDetails":{}}"#,
    )
    .expect("write");
    let value = store.load().expect("load");
    assert_eq!(value.total, 5);
    assert_eq!(value.selections.total(), 0);
}

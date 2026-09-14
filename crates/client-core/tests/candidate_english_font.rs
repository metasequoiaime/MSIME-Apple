use msime_client_core::preferences::{Preferences, PreferencesStore};

#[test]
fn old_documents_and_roundtrip_preserve_host_neutral_defaults() {
    let original = Preferences::default();
    let json = serde_json::to_value(&original).unwrap();
    assert!(json.get("candidate_english_font").is_none());
    let loaded: Preferences = serde_json::from_value(json).unwrap();
    assert!(loaded.candidate_english_font.is_none());
    let dir = tempfile::tempdir().unwrap();
    let store = PreferencesStore::new(dir.path());
    let preferences = Preferences {
        candidate_english_font: Some("示例 Latin W03".into()),
        ..original
    };
    store.save(0, preferences).unwrap();
    assert_eq!(
        store
            .load()
            .unwrap()
            .preferences
            .candidate_english_font
            .as_deref(),
        Some("示例 Latin W03")
    );
}

#[test]
fn english_font_rejects_invalid_names() {
    for name in [
        "".to_owned(),
        "x".repeat(129),
        "bad\0name".into(),
        "bad\nname".into(),
        "bad\u{85}name".into(),
    ] {
        let preferences = Preferences {
            candidate_english_font: Some(name),
            ..Preferences::default()
        };
        assert!(preferences.validate().is_err());
    }
    let preferences = Preferences {
        candidate_english_font: Some("x".repeat(128)),
        ..Preferences::default()
    };
    assert!(preferences.validate().is_ok());
}

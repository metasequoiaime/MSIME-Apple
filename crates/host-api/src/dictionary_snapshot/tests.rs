#[test]
fn snapshot_module_is_present() {
    assert_eq!(super::HANDLE_LIMIT, 8);
}

#[test]
fn activation_swaps_all_state_roots_and_consumes_handle() {
    use super::*;
    use msime_engine_bridge::EngineOptions;
    use std::fs;
    use std::path::Path;

    let root = tempfile::tempdir().unwrap();
    let active = root.path().join("active");
    let staged = root.path().join("staged");
    for name in ["resources", "user", "cache", "dictionaries"] {
        fs::create_dir_all(active.join(name)).unwrap();
        fs::create_dir_all(staged.join(name)).unwrap();
        fs::write(active.join(name).join("marker"), b"old").unwrap();
        fs::write(staged.join(name).join("marker"), b"new").unwrap();
    }
    let make = |base: &Path| EngineOptions {
        resources: base.join("resources").to_str().unwrap().into(),
        user_data: base.join("user").to_str().unwrap().into(),
        cache: base.join("cache").to_str().unwrap().into(),
        dictionaries: base.join("dictionaries").to_str().unwrap().into(),
        scheme: 0,
        shuangpin_profile: 0,
        learning: false,
        autocorrect: true,
        helpcode: false,
        helpcode_schema: "ziranma".into(),
        chinese_punctuation: true,
        paired_punctuation: true,
        punctuation_lock: 0,
        frequency_mode: "promote".into(),
        frequency_trigger_count: 1,
        frequency_linear_step: 1,
        mixed_english: true,
        english_minimum_prefix: 2,
        mixed_emoji: false,
        mixed_kaomoji: false,
        local_unicode: true,
        local_date_time: true,
        local_quick_phrase: true,
        local_emoji: true,
        local_kaomoji: true,
        local_super_jianpin: true,
        local_temporary_english: true,
        local_temporary_japanese: true,
    };
    let active_options = make(&active);
    let staged_options = make(&staged);
    let expected = super::version_without_access(&active_options).unwrap();
    let directory = tempfile::tempdir_in(root.path()).unwrap();
    registry().lock().unwrap().insert(
        123,
        Prepared {
            directory,
            active_options,
            options: staged_options,
            source_version: expected.clone(),
        },
    );
    let wrong = "0".repeat(64);
    assert!(activate(123, &wrong).is_err());
    for name in ["user", "cache", "dictionaries"] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"old");
    }
    fs::remove_dir_all(staged.join("cache")).unwrap();
    assert!(activate(123, &expected).is_err());
    for name in ["user", "cache", "dictionaries"] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"old");
    }
    fs::create_dir_all(staged.join("cache")).unwrap();
    fs::write(staged.join("cache").join("marker"), b"new").unwrap();
    assert_eq!(
        activate(123, &expected).unwrap(),
        serde_json::json!({"activated": true})
    );
    for name in ["user", "cache", "dictionaries"] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"new");
    }
    assert!(!registry().lock().unwrap().contains_key(&123));
    assert!(activate(123, &expected).is_err());
}

#[test]
fn snapshot_module_is_present() {
    assert_eq!(super::HANDLE_LIMIT, 8);
}

#[test]
fn activation_swaps_all_state_roots_and_consumes_handle() {
    activation_case(false, false, 123);
    activation_case(true, false, 123);
}

#[test]
fn activation_rejects_live_session_before_swapping() {
    // The registry is process-global; use a distinct fixture handle so this
    // test can run in parallel with the successful activation cases.
    activation_case(false, true, 125);
    activation_case(true, true, 125);
}

#[test]
fn discard_does_not_require_maintenance_lock_for_live_paths() {
    use super::*;
    use msime_client_core::dictionary_access::DictionaryAccess;
    use msime_engine_bridge::EngineOptions;
    use std::fs;

    let root = tempfile::tempdir().unwrap();
    let user = root.path().join("user");
    let dictionaries = root.path().join("dictionaries");
    fs::create_dir_all(&user).unwrap();
    fs::create_dir_all(&dictionaries).unwrap();
    let session_access = DictionaryAccess::try_session(&user, &dictionaries)
        .unwrap()
        .unwrap();
    let directory = tempfile::tempdir_in(root.path()).unwrap();
    let options = EngineOptions {
        resources: root.path().join("resources").to_string_lossy().into_owned(),
        user_data: user.to_string_lossy().into_owned(),
        cache: root.path().join("cache").to_string_lossy().into_owned(),
        dictionaries: dictionaries.to_string_lossy().into_owned(),
        scheme: 0,
        shuangpin_profile: 0,
        shuangpin_preedit_uses_raw: true,
        learning: false,
        autocorrect_transposition: true,
        autocorrect_neighbor: true,
        fuzzy_pinyin_rules: 0,
        wubi_mixed_pinyin: false,
        helpcode: false,
        show_helpcode: true,
        helpcode_schema: "ziranma".into(),
        chinese_punctuation: true,
        paired_punctuation: true,
        punctuation_lock: 0,
        frequency_mode: "promote".into(),
        frequency_trigger_count: 1,
        frequency_linear_step: 1,
        mixed_english: true,
        english_minimum_prefix: 5,
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
    registry().lock().unwrap().insert(
        456,
        Prepared {
            directory,
            active_options: options.clone(),
            options,
            source_version: String::new(),
        },
    );
    assert_eq!(
        discard(456).unwrap(),
        serde_json::json!({"discarded": true})
    );
    assert!(!registry().lock().unwrap().contains_key(&456));
    drop(session_access);
}

fn activation_case(nested_dictionaries: bool, hold_session: bool, handle: u64) {
    use super::*;
    use msime_client_core::dictionary_access::DictionaryAccess;
    use msime_engine_bridge::EngineOptions;
    use std::fs;
    use std::path::Path;

    let root = tempfile::tempdir().unwrap();
    let active = root.path().join("active");
    let staged = root.path().join("staged");
    let dictionaries = if nested_dictionaries {
        "user/dictionaries/generation"
    } else {
        "dictionaries"
    };
    for name in ["resources", "user", "cache", dictionaries] {
        fs::create_dir_all(active.join(name)).unwrap();
        fs::create_dir_all(staged.join(name)).unwrap();
        fs::write(active.join(name).join("marker"), b"old").unwrap();
        fs::write(staged.join(name).join("marker"), b"new").unwrap();
    }
    let activation_id = "00112233-4455-6677-8899-aabbccddeeff";
    fs::write(
        staged.join("user").join(super::ACTIVATION_RECEIPT_NAME),
        activation_id,
    )
    .unwrap();
    let make = |base: &Path| EngineOptions {
        resources: base.join("resources").to_str().unwrap().into(),
        user_data: base.join("user").to_str().unwrap().into(),
        cache: base.join("cache").to_str().unwrap().into(),
        dictionaries: base.join(dictionaries).to_str().unwrap().into(),
        scheme: 0,
        shuangpin_profile: 0,
        shuangpin_preedit_uses_raw: true,
        learning: false,
        autocorrect_transposition: true,
        autocorrect_neighbor: true,
        fuzzy_pinyin_rules: 0,
        wubi_mixed_pinyin: false,
        helpcode: false,
        show_helpcode: true,
        helpcode_schema: "ziranma".into(),
        chinese_punctuation: true,
        paired_punctuation: true,
        punctuation_lock: 0,
        frequency_mode: "promote".into(),
        frequency_trigger_count: 1,
        frequency_linear_step: 1,
        mixed_english: true,
        english_minimum_prefix: 5,
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
        handle,
        Prepared {
            directory,
            active_options: active_options.clone(),
            options: staged_options,
            source_version: expected.clone(),
        },
    );
    let session_access = if hold_session {
        Some(
            DictionaryAccess::try_session(
                Path::new(&active_options.user_data),
                Path::new(&active_options.dictionaries),
            )
            .unwrap()
            .unwrap(),
        )
    } else {
        None
    };
    if let Some(session_access) = session_access {
        assert!(activate(handle, &expected).is_err());
        for name in ["user", "cache", dictionaries] {
            assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"old");
        }
        drop(session_access);
    }
    let wrong = "0".repeat(64);
    assert!(activate(handle, &wrong).is_err());
    for name in ["user", "cache", dictionaries] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"old");
    }
    fs::remove_dir_all(staged.join("cache")).unwrap();
    assert!(activate(handle, &expected).is_err());
    for name in ["user", "cache", dictionaries] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"old");
    }
    let backup_path = |path: &Path| {
        path.with_file_name(format!(
            "{}.msime-snapshot-old-{handle}",
            path.file_name().unwrap().to_string_lossy()
        ))
    };
    for path in [
        backup_path(&active.join("user")),
        backup_path(&active.join("cache")),
        backup_path(&active.join(dictionaries)),
    ] {
        assert!(!path.exists());
    }
    fs::create_dir_all(staged.join("cache")).unwrap();
    fs::write(staged.join("cache").join("marker"), b"new").unwrap();
    assert_eq!(
        activate(handle, &expected).unwrap(),
        serde_json::json!({"activated": true})
    );
    for name in ["user", "cache", dictionaries] {
        assert_eq!(fs::read(active.join(name).join("marker")).unwrap(), b"new");
    }
    assert_eq!(
        super::activation_receipt(&active_options)
            .unwrap()
            .as_deref(),
        Some(activation_id)
    );
    assert!(!registry().lock().unwrap().contains_key(&handle));
    assert!(activate(handle, &expected).is_err());
}

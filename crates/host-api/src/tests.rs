//! Unit tests for the parent module, in their own file because the module
//! is large enough that mixing them with the implementation obscured both.
//! Same `mod tests` as before, so `use super::*` still names the parent.

use super::*;

#[test]
fn windows_legacy_mixed_input_is_imported_without_leaking_other_config() {
    let mut preferences = Preferences::default();
    assert!(apply_windows_legacy_mixed_input(
        "[general]\ncn_en_mixed_input = false\ncn_en_mixed_input_min_chars = 5\nemoji_mixed_input = true\nkaomoji_mixed_input = true\ndiagnostic_log = true\n",
        &mut preferences,
    ));
    assert!(!preferences.mixed_input.english);
    assert_eq!(preferences.mixed_input.minimum_prefix, 5);
    assert!(preferences.mixed_input.emoji);
    assert!(preferences.mixed_input.kaomoji);
    assert!(!preferences.diagnostic_log.server);
    assert!(!preferences.diagnostic_log.tsf);
}

#[test]
fn windows_legacy_mixed_input_ignores_invalid_values_and_documents() {
    let mut preferences = Preferences::default();
    assert!(!apply_windows_legacy_mixed_input(
        "[general]\ncn_en_mixed_input_min_chars = 9\n",
        &mut preferences,
    ));
    assert_eq!(preferences.mixed_input.minimum_prefix, 2);
    assert!(!apply_windows_legacy_mixed_input(
        "not toml",
        &mut preferences
    ));
}

#[test]
fn local_mode_resource_gates_preserve_unrelated_modes() {
    let root = tempfile::tempdir().unwrap();
    for name in ["others.db", "english.db", "dict_japanese.dat"] {
        std::fs::write(root.path().join(name), b"fixture").unwrap();
    }
    let mut options = EngineOptions {
        resources: root.path().to_string_lossy().into_owned(),
        user_data: root.path().to_string_lossy().into_owned(),
        cache: root.path().to_string_lossy().into_owned(),
        dictionaries: root.path().to_string_lossy().into_owned(),
        scheme: 0,
        shuangpin_profile: 0,
        shuangpin_preedit_uses_raw: true,
        learning: false,
        autocorrect_transposition: false,
        autocorrect_neighbor: false,
        fuzzy_pinyin_rules: 0,
        wubi_mixed_pinyin: false,
        helpcode: false,
        show_helpcode: false,
        helpcode_schema: "ziranma".into(),
        chinese_punctuation: true,
        paired_punctuation: true,
        punctuation_lock: 0,
        frequency_mode: "disabled".into(),
        frequency_trigger_count: 1,
        frequency_linear_step: 1,
        mixed_english: false,
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
        sentence_alternatives: true,
    };
    apply_local_mode_resource_gates(&mut options);
    assert!(options.local_unicode);
    assert!(options.local_date_time);
    assert!(options.local_quick_phrase);
    assert!(options.local_super_jianpin);
    assert!(options.local_emoji);
    assert!(options.local_kaomoji);
    assert!(options.local_temporary_english);
    assert!(options.local_temporary_japanese);

    std::fs::remove_file(root.path().join("others.db")).unwrap();
    std::fs::remove_file(root.path().join("dict_japanese.dat")).unwrap();
    apply_local_mode_resource_gates(&mut options);
    assert!(!options.local_emoji);
    assert!(!options.local_kaomoji);
    assert!(!options.local_temporary_japanese);
    assert!(options.local_temporary_english);
    assert!(options.local_unicode);
    assert!(options.local_date_time);
    assert!(options.local_quick_phrase);
    assert!(options.local_super_jianpin);
}

#[test]
fn doubao_frame_codec_is_available_through_c_abi() {
    let request = msime_client_core::voice::doubao_frame::encode_json_frame(
        9,
        0,
        1,
        br#"{"result":{"text":"fixture"}}"#,
    );
    let mut response = request[..4].to_vec();
    response.extend_from_slice(&request[8..12]);
    response.extend_from_slice(&request[12..]);
    let decoded =
        read(unsafe { msime_client_doubao_decode_frame(response.as_ptr(), response.len()) });
    assert_eq!(decoded["ok"], true);
    assert_eq!(decoded["value"]["last"], false);
    assert_eq!(
        decoded["value"]["payload"],
        r#"{"result":{"text":"fixture"}}"#
    );

    let error = [0x11, 0xf0, 0x11, 0, 0, 0, 0, 7, 0, 0, 0, 42];
    let decoded_error =
        read(unsafe { msime_client_doubao_decode_frame(error.as_ptr(), error.len()) });
    assert_eq!(decoded_error["value"]["error_code"], 7);

    let mut start = vec![0u8; 4096];
    let mut written = 0usize;
    assert!(unsafe {
        msime_client_doubao_start_frame(
            true,
            false,
            true,
            b"table".as_ptr(),
            5,
            start.as_mut_ptr(),
            start.len(),
            &mut written,
        )
    });
    assert_eq!(&start[..4], &[0x11, 0x11, 0x11, 0]);
    assert!(written > 12);

    let mut audio = vec![0u8; 1024];
    let mut audio_written = 0usize;
    assert!(unsafe {
        msime_client_doubao_audio_frame(
            2,
            [0u8, 1, 2, 3].as_ptr(),
            4,
            true,
            audio.as_mut_ptr(),
            audio.len(),
            &mut audio_written,
        )
    });
    assert_eq!(&audio[..4], &[0x11, 0x23, 0x11, 0]);
}

#[test]
fn surface_route_boundary_resolves_panels_and_rejects_bad_buffers() {
    let parse = |value: &str| {
        // SAFETY: the slice outlives the call.
        read(unsafe { msime_client_parse_surface_route(value.as_ptr(), value.len()) })
    };

    let keyboard = parse("keyboard");
    assert_eq!(keyboard["ok"], true);
    assert_eq!(keyboard["value"]["route"], "keyboard");
    assert_eq!(keyboard["value"]["panel"]["label"], "keyboard-panel");
    assert_eq!(keyboard["value"]["panel"]["width"], 1100);

    // The local clipboard panel the desktop host ships must stay reachable.
    let clipboard = parse("clipboard");
    assert_eq!(clipboard["value"]["panel"]["label"], "clipboard-panel");
    assert_eq!(clipboard["value"]["panel"]["height"], 620);

    let deep_link = parse("settings:voice");
    assert_eq!(deep_link["ok"], true);
    assert_eq!(deep_link["value"]["route"], "settings:voice");
    // Settings is the main window, so it carries no panel geometry.
    assert!(deep_link["value"].get("panel").is_none());

    for rejected in ["", "account", "settings:unknown", "Settings"] {
        assert_eq!(parse(rejected)["ok"], false, "accepted {rejected:?}");
    }

    // A null buffer and an oversized length are refused, not dereferenced.
    assert_eq!(
        read(unsafe { msime_client_parse_surface_route(std::ptr::null(), 8) })["ok"],
        false
    );
    let value = "settings";
    assert_eq!(
        read(unsafe { msime_client_parse_surface_route(value.as_ptr(), 4096) })["ok"],
        false
    );
    let invalid = [0xff_u8, 0xfe];
    assert_eq!(
        read(unsafe { msime_client_parse_surface_route(invalid.as_ptr(), invalid.len()) })["ok"],
        false
    );
}

#[test]
fn host_capability_boundary_describes_each_platform() {
    let capabilities = |value: &str| {
        // SAFETY: the slice outlives the call.
        read(unsafe { msime_client_host_capabilities(value.as_ptr(), value.len()) })
    };

    let linux = capabilities("linux");
    assert_eq!(linux["ok"], true);
    assert_eq!(linux["value"]["platform"], "linux");
    assert_eq!(linux["value"]["restart_input_method"], true);
    assert_eq!(linux["value"]["ime_mode_scope"], true);

    let windows = capabilities("windows");
    assert_eq!(windows["value"]["restart_input_method"], true);
    assert_eq!(windows["value"]["panel_windows"], true);
    // Typing statistics used to be gated on an Android user-agent match.
    assert_eq!(windows["value"]["typing_statistics"], true);

    let macos = capabilities("macos");
    assert_eq!(macos["value"]["restart_input_method"], true);
    assert_eq!(macos["value"]["candidate_follow_cursor"], true);

    let android = capabilities("android");
    assert_eq!(android["value"]["panel_windows"], false);
    assert_eq!(android["value"]["window_chrome"], false);

    assert_eq!(capabilities("bsd")["ok"], false);
    assert_eq!(capabilities("")["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_host_capabilities(std::ptr::null(), 5) })["ok"],
        false
    );
}

#[test]
fn abi_version_reports_the_surface_route_revision() {
    assert_eq!(msime_client_abi_version(), 2);
}
#[test]
fn native_preference_save_clears_history_only_after_successful_disable() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().to_str().unwrap();
    let store = PreferencesStore::new(directory.path());
    let mut enabled = store
        .save(
            0,
            Preferences {
                clipboard_history: true,
                ..Preferences::default()
            },
        )
        .unwrap();
    assert!(store
        .capture_clipboard_text("synthetic saved history".into())
        .unwrap());
    let history = directory.path().join("clipboard_history.json");
    let original = std::fs::read(&history).unwrap();
    let save = |revision, snapshot: &PreferencesSnapshot| {
        let bytes = serde_json::to_vec(snapshot).unwrap();
        read(unsafe {
            msime_client_save_preferences(
                path.as_ptr(),
                path.len(),
                revision,
                bytes.as_ptr(),
                bytes.len(),
            )
        })
    };
    enabled.preferences.clipboard_history = false;
    assert_eq!(save(0, &enabled)["ok"], false);
    assert_eq!(std::fs::read(&history).unwrap(), original);
    let result = save(enabled.revision, &enabled);
    assert_eq!(result["ok"], true);
    assert_eq!(result["value"]["revision"], enabled.revision + 1);
    assert!(
        !history.exists(),
        "successful native disable retained clipboard history"
    );
    assert!(!store
        .capture_clipboard_text("synthetic stopped capture".into())
        .unwrap());
    let mut restored = store.load().unwrap();
    restored.preferences.clipboard_history = true;
    assert_eq!(save(restored.revision, &restored)["ok"], true);
    assert!(store
        .capture_clipboard_text("synthetic new capture".into())
        .unwrap());
    let before = std::fs::read(&history).unwrap();
    let current = store.load().unwrap();
    assert_eq!(save(current.revision, &current)["ok"], true);
    assert_eq!(std::fs::read(&history).unwrap(), before);
    std::fs::remove_file(&history).unwrap();
    std::fs::create_dir(&history).unwrap();
    let mut disabled = store.load().unwrap();
    disabled.preferences.clipboard_history = false;
    assert_eq!(save(disabled.revision, &disabled)["ok"], false);
    assert!(!store.load().unwrap().preferences.clipboard_history);
    assert_eq!(store.load().unwrap().revision, disabled.revision + 1);
    assert!(history.is_dir());
}

#[test]
fn mixed_input_changes_defer_until_composition_ends() {
    use msime_client_core::preferences::MixedInputPreferences;
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    let before = read(msime_client_view(handle));
    let mut preferences = Preferences {
        mixed_input: MixedInputPreferences {
            english: false,
            minimum_prefix: 8,
            emoji: true,
            kaomoji: true,
        },
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
    assert_eq!(read(msime_client_view(handle)), before);
    SESSIONS.with(|sessions| {
        let sessions = sessions.borrow();
        let options = &sessions[&handle].options;
        assert!(options.mixed_english);
        assert!(!options.mixed_emoji);
        assert!(!options.mixed_kaomoji);
    });
    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| {
        let sessions = sessions.borrow();
        let options = &sessions[&handle].options;
        assert!(!options.mixed_english);
        assert_eq!(options.english_minimum_prefix, 8);
        assert!(options.mixed_emoji && options.mixed_kaomoji);
    });
    preferences.mixed_input.minimum_prefix = 9;
    assert_eq!(update(handle, 2, &preferences)["ok"], false);
    read(msime_client_destroy(handle));
}
#[test]
fn frequency_changes_wait_for_composition_and_reject_invalid_updates() {
    use msime_client_core::preferences::{FrequencyMode, FrequencyPreferences};
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    let before = read(msime_client_view(handle));
    let mut preferences = Preferences {
        frequency: FrequencyPreferences {
            mode: FrequencyMode::Linear,
            trigger_count: 3,
            linear_step: 2,
        },
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
    assert_eq!(read(msime_client_view(handle)), before);
    SESSIONS
        .with(|sessions| assert_eq!(sessions.borrow()[&handle].options.frequency_mode, "promote"));
    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| {
        let sessions = sessions.borrow();
        assert_eq!(sessions[&handle].options.frequency_mode, "linear");
        assert_eq!(sessions[&handle].options.frequency_trigger_count, 3);
        assert_eq!(sessions[&handle].options.frequency_linear_step, 2);
    });
    preferences.frequency.trigger_count = 0;
    assert_eq!(update(handle, 2, &preferences)["ok"], false);
    read(msime_client_destroy(handle));
}

#[test]
fn fuzzy_pinyin_changes_wait_for_composition_and_disabled_rules_are_retained() {
    use msime_client_core::preferences::{FuzzyPinyinPreferences, FuzzyPinyinRule};
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'z', false));
    let mut preferences = Preferences {
        fuzzy_pinyin: FuzzyPinyinPreferences {
            enabled: true,
            rules: [FuzzyPinyinRule::ZZh].into_iter().collect(),
            seeded: false,
        },
        ..Preferences::default()
    };
    let queued = update(handle, 1, &preferences);
    assert_eq!(queued["value"]["deferred"], true);
    SESSIONS.with(|sessions| assert_eq!(sessions.borrow()[&handle].options.fuzzy_pinyin_rules, 0));
    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| assert_eq!(sessions.borrow()[&handle].options.fuzzy_pinyin_rules, 1));

    preferences.fuzzy_pinyin.enabled = false;
    let disabled = update(handle, 2, &preferences);
    assert_eq!(disabled["value"]["deferred"], false);
    SESSIONS.with(|sessions| {
        let session = &sessions.borrow()[&handle];
        assert_eq!(session.options.fuzzy_pinyin_rules, 0);
        assert!(!session.applied.fuzzy_pinyin.enabled);
        assert!(session
            .applied
            .fuzzy_pinyin
            .rules
            .contains(&FuzzyPinyinRule::ZZh));
    });
    read(msime_client_destroy(handle));
}

#[test]
fn wubi_mixed_pinyin_reaches_engine_and_applies_after_composition() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'a', false));
    let mut preferences = Preferences {
        scheme: InputScheme::Wubi,
        wubi_mixed_pinyin: true,
        ..Preferences::default()
    };
    let queued = update(handle, 1, &preferences);
    assert_eq!(queued["value"]["deferred"], true);
    SESSIONS.with(|sessions| {
        assert!(!sessions.borrow()[&handle].options.wubi_mixed_pinyin);
    });

    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| {
        let session = &sessions.borrow()[&handle];
        assert!(session.options.wubi_mixed_pinyin);
        assert!(session.applied.wubi_mixed_pinyin);
    });

    preferences.wubi_mixed_pinyin = false;
    let disabled = update(handle, 2, &preferences);
    assert_eq!(disabled["value"]["deferred"], false);
    SESSIONS.with(|sessions| {
        assert!(!sessions.borrow()[&handle].options.wubi_mixed_pinyin);
    });
    read(msime_client_destroy(handle));
}

#[test]
fn japanese_mode_switch_defers_and_restores_chinese_profile() {
    use msime_client_core::preferences::ChineseScheme;
    let dir = tempfile::tempdir().unwrap();
    let chinese = Preferences {
        scheme: InputScheme::Shuangpin,
        shuangpin_profile: ShuangpinProfile::Microsoft,
        last_chinese_scheme: Some(ChineseScheme::Shuangpin),
        ..chinese_preferences()
    };
    let handle = test_host_preferences(dir.path(), chinese.clone());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'b', false));
    read(msime_client_character(handle, b';', false));
    let japanese = Preferences {
        scheme: InputScheme::Japanese,
        touch_keyboard_layout: TouchKeyboardLayout::NineKey,
        ..chinese.clone()
    };
    let queued = update(handle, 1, &japanese);
    assert_eq!(queued["value"]["deferred"], true);
    assert_eq!(
        queued["value"]["view"]["touch_keyboard_layout"],
        "twenty_six_key"
    );
    let committed = read(msime_client_command(handle, 2));
    assert_eq!(committed["value"]["commit"], "b;");
    assert_eq!(committed["value"]["commit_context"]["scheme"], 1);
    assert_eq!(committed["value"]["view"]["scheme"], 3);
    assert_eq!(committed["value"]["view"]["nine_key"], false);
    assert_eq!(
        committed["value"]["view"]["touch_keyboard_layout"],
        "nine_key"
    );
    let kana = read(msime_client_character(handle, b'a', false));
    assert_eq!(kana["ok"], true);
    assert_eq!(kana["value"]["view"]["preedit"], "a");
    assert_eq!(kana["value"]["view"]["reading"], "あ");
    assert_eq!(kana["value"]["view"]["scheme"], 3);
    assert_eq!(kana["value"]["view"]["candidates"][0]["text"], "あ");
    assert_eq!(kana["value"]["view"]["candidates"][1]["text"], "ア");
    let small_kana = read(msime_client_command(handle, 10));
    assert_eq!(small_kana["value"]["handled"], true);
    assert_eq!(small_kana["value"]["view"]["reading"], "ぁ");
    let committed_small_kana = read(msime_client_command(handle, 11));
    assert_eq!(committed_small_kana["value"]["commit"], "ぁ");
    assert_eq!(committed_small_kana["value"]["view"]["reading"], "");
    read(msime_client_character(handle, b'a', false));
    let committed_kana = read(msime_client_command(handle, 11));
    assert_eq!(committed_kana["value"]["commit"], "あ");
    assert_eq!(committed_kana["value"]["view"]["reading"], "");
    read(msime_client_command(handle, 3));
    read(msime_client_character(handle, b'n', false));
    let syllable_separator = read(msime_client_character(handle, b'\'', false));
    assert_eq!(syllable_separator["ok"], true);
    assert_eq!(
        syllable_separator["value"]["view"]["candidates"][0]["text"],
        "ん"
    );
    assert_eq!(update(handle, 2, &chinese)["value"]["deferred"], true);
    read(msime_client_command(handle, 3));
    assert_eq!(
        read(msime_client_view(handle))["value"]["touch_keyboard_layout"],
        "twenty_six_key"
    );
    read(msime_client_character(handle, b'b', false));
    assert_eq!(
        read(msime_client_character(handle, b';', false))["value"]["view"]["editing_text"],
        "b;"
    );
    read(msime_client_destroy(handle));
}

#[test]
fn japanese_commands_are_unhandled_for_non_japanese_schemes() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    let typed = read(msime_client_character(handle, b'a', false));
    assert_eq!(typed["value"]["view"]["reading"], "");

    let variant = read(msime_client_command(handle, 10));
    assert_eq!(variant["value"]["handled"], false);
    assert_eq!(variant["value"]["view"]["editing_text"], "a");
    assert_eq!(variant["value"]["view"]["reading"], "");

    let reading = read(msime_client_command(handle, 11));
    assert_eq!(reading["value"]["handled"], false);
    assert!(reading["value"]["commit"].is_null());
    assert_eq!(reading["value"]["view"]["reading"], "");
    read(msime_client_destroy(handle));
}

#[test]
fn japanese_commands_apply_to_the_twenty_six_key_scheme() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host_preferences(
        dir.path(),
        Preferences {
            scheme: InputScheme::Japanese,
            touch_keyboard_layout: TouchKeyboardLayout::TwentySixKey,
            ..chinese_preferences()
        },
    );
    read(msime_client_focus(handle, true));
    let typed = read(msime_client_character(handle, b'a', false));
    assert_eq!(
        typed["value"]["view"]["touch_keyboard_layout"],
        "twenty_six_key"
    );
    assert_eq!(typed["value"]["view"]["reading"], "あ");

    let variant = read(msime_client_command(handle, 10));
    assert_eq!(variant["value"]["handled"], true);
    assert_eq!(variant["value"]["view"]["reading"], "ぁ");
    let committed = read(msime_client_command(handle, 11));
    assert_eq!(committed["value"]["commit"], "ぁ");
    assert_eq!(committed["value"]["view"]["reading"], "");
    read(msime_client_destroy(handle));
}

#[test]
fn handwriting_layout_is_exposed_only_after_pending_composition_finishes() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'n', false));
    read(msime_client_character(handle, b'i', false));
    let handwriting = Preferences {
        touch_keyboard_layout: TouchKeyboardLayout::Handwriting,
        ..Preferences::default()
    };
    let queued = update(handle, 1, &handwriting);
    assert_eq!(queued["value"]["deferred"], true);
    assert_eq!(
        queued["value"]["view"]["touch_keyboard_layout"],
        "twenty_six_key"
    );
    let finished = read(msime_client_command(handle, 9));
    assert_eq!(finished["value"]["commit"], "ni");
    assert_eq!(
        finished["value"]["view"]["touch_keyboard_layout"],
        "handwriting"
    );
    assert_eq!(finished["value"]["view"]["nine_key"], false);
    read(msime_client_destroy(handle));
}

#[test]
fn nine_key_mode_and_spelling_identity_cross_the_host_boundary() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    let enabled = read(msime_client_set_nine_key_mode(handle, true));
    assert_eq!(enabled["value"]["nine_key"], true);
    let typed = read(msime_client_character(handle, b'6', false));
    assert_eq!(typed["value"]["handled"], true);
    let view = &typed["value"]["view"];
    let generation = view["generation"].as_u64().unwrap();
    assert!(!view["nine_key_spellings"].as_array().unwrap().is_empty());
    assert_eq!(
        read(msime_client_choose_nine_key_spelling(
            handle,
            generation - 1,
            0
        ))["ok"],
        false
    );
    let selected = read(msime_client_choose_nine_key_spelling(handle, generation, 0));
    assert_eq!(selected["value"]["handled"], true);
    assert_eq!(
        read(msime_client_set_nine_key_mode(handle, false))["ok"],
        false
    );
    read(msime_client_command(handle, 3));
    assert_eq!(
        read(msime_client_set_nine_key_mode(handle, false))["value"]["nine_key"],
        false
    );

    let mut preferences = Preferences {
        candidate_page_size: 4,
        touch_keyboard_layout: TouchKeyboardLayout::NineKey,
        ..Preferences::default()
    };
    assert_eq!(
        update(handle, 1, &preferences)["value"]["view"]["nine_key"],
        true
    );
    preferences.learning = false;
    assert_eq!(
        update(handle, 2, &preferences)["value"]["view"]["nine_key"],
        true
    );
    preferences.touch_keyboard_layout = TouchKeyboardLayout::TwentySixKey;
    assert_eq!(
        update(handle, 3, &preferences)["value"]["view"]["nine_key"],
        false
    );
    preferences.touch_keyboard_layout = TouchKeyboardLayout::Handwriting;
    assert_eq!(
        update(handle, 4, &preferences)["value"]["view"]["touch_keyboard_layout"],
        "handwriting"
    );
    assert_eq!(read(msime_client_view(handle))["value"]["nine_key"], false);
    assert_eq!(
        read(msime_client_set_nine_key_mode(handle, true))["value"]["nine_key"],
        true
    );
    preferences.candidate_page_size = 3;
    assert_eq!(
        update(handle, 5, &preferences)["value"]["view"]["nine_key"],
        true
    );
    preferences.scheme = InputScheme::Wubi;
    assert_eq!(
        update(handle, 6, &preferences)["value"]["view"]["nine_key"],
        false
    );
    assert_eq!(
        read(msime_client_set_nine_key_mode(handle, true))["ok"],
        false
    );
    read(msime_client_destroy(handle));

    let persisted_dir = tempfile::tempdir().unwrap();
    let persisted = test_host_preferences(
        persisted_dir.path(),
        Preferences {
            touch_keyboard_layout: TouchKeyboardLayout::NineKey,
            ..Preferences::default()
        },
    );
    assert_eq!(
        read(msime_client_view(persisted))["value"]["nine_key"],
        true
    );
    read(msime_client_destroy(persisted));
}

#[test]
fn nine_key_digits_offer_ranked_english_across_the_host_boundary() {
    use msime_client_core::preferences::MixedInputPreferences;

    let dir = tempfile::tempdir().unwrap();
    let dictionaries = dir.path().join("dictionaries");
    std::fs::create_dir_all(&dictionaries).unwrap();
    let db = rusqlite::Connection::open(dictionaries.join("english.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);
         INSERT INTO english_words VALUES('ok','ok',900);
         INSERT INTO english_words VALUES('old','old',1000);
         INSERT INTO english_words VALUES('older','older',800);",
    )
    .unwrap();
    drop(db);

    let handle = test_host_preferences(
        dir.path(),
        Preferences {
            candidate_page_size: 2,
            learning: false,
            touch_keyboard_layout: TouchKeyboardLayout::NineKey,
            mixed_input: MixedInputPreferences {
                english: true,
                minimum_prefix: 2,
                emoji: false,
                kaomoji: false,
            },
            ..chinese_preferences()
        },
    );
    read(msime_client_focus(handle, true));
    assert_eq!(
        read(msime_client_character(handle, b'6', false))["value"]["handled"],
        true
    );
    let typed = read(msime_client_character(handle, b'5', false));
    assert_eq!(typed["value"]["view"]["nine_key"], true);

    let complete = read(msime_client_all_candidates(handle));
    let candidates = complete["value"]["candidates"].as_array().unwrap();
    let position = |text: &str| {
        candidates
            .iter()
            .position(|candidate| candidate["text"] == text)
            .unwrap_or_else(|| panic!("missing synthetic candidate {text}"))
    };
    let ok = position("ok");
    assert!(ok < position("old"));
    assert!(ok < position("older"));

    let generation = complete["value"]["generation"].as_u64().unwrap();
    let index = candidates[ok]["id"]["index"].as_u64().unwrap() as usize;
    let selected = read(msime_client_select_any_candidate(handle, generation, index));
    assert_eq!(selected["value"]["handled"], true);
    assert_eq!(selected["value"]["commit"], "ok");
    assert_eq!(read(msime_client_destroy(handle))["ok"], true);
}

#[test]
fn helpcode_defaults_follow_windows_for_each_pinyin_scheme() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    SESSIONS.with(|sessions| {
        let session = &sessions.borrow()[&handle];
        assert!(session.options.helpcode);
        assert_eq!(session.options.helpcode_schema, "ziranma");
        assert!(!session.options.show_helpcode);
    });

    let shuangpin = Preferences {
        scheme: InputScheme::Shuangpin,
        ..chinese_preferences()
    };
    assert_eq!(update(handle, 1, &shuangpin)["value"]["deferred"], false);
    SESSIONS.with(|sessions| {
        let session = &sessions.borrow()[&handle];
        assert!(session.options.helpcode);
        assert_eq!(session.options.helpcode_schema, "lantian");
        assert!(session.options.show_helpcode);
    });
    read(msime_client_destroy(handle));
}

#[test]
fn english_completion_boundary_is_read_only_and_case_insensitive() {
    let dir = tempfile::tempdir().unwrap();
    let dictionaries = dir.path().join("dictionaries");
    std::fs::create_dir_all(&dictionaries).unwrap();
    let db = rusqlite::Connection::open(dictionaries.join("english.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);
         INSERT INTO english_words VALUES('hello','hello',1000);
         INSERT INTO english_words VALUES('help','help',900);
         INSERT INTO english_words VALUES('helium','helium',800);",
    )
    .unwrap();
    drop(db);
    let handle = test_host(dir.path());
    let before = read(msime_client_view(handle))["value"].clone();
    let prefix = b"He";
    let result =
        read(unsafe { msime_client_english_completions(handle, prefix.as_ptr(), prefix.len(), 2) });
    assert_eq!(result["ok"], true, "{result}");
    assert_eq!(result["value"]["completions"], json!(["hello", "help"]));
    assert_eq!(read(msime_client_view(handle))["value"], before);
    let invalid = read(unsafe { msime_client_english_completions(handle, b"he!".as_ptr(), 3, 2) });
    assert_eq!(invalid["ok"], false);
    read(msime_client_destroy(handle));
}

#[test]
fn helpcode_settings_switch_independently_after_composition() {
    use msime_client_core::preferences::{HelpcodePreferences, HelpcodeSchema};
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    let before = read(msime_client_view(handle))["value"].clone();
    let mut preferences = Preferences {
        quanpin_helpcode: HelpcodePreferences {
            enabled: false,
            schema: HelpcodeSchema::Xiaohe,
            show_in_candidate_window: false,
        },
        shuangpin_helpcode: HelpcodePreferences {
            enabled: true,
            schema: HelpcodeSchema::Shouyou2,
            show_in_candidate_window: true,
        },
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
    assert_eq!(read(msime_client_view(handle))["value"], before);
    SESSIONS.with(|sessions| assert!(sessions.borrow()[&handle].options.helpcode));
    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| {
        assert!(!sessions.borrow()[&handle].options.helpcode);
        assert_eq!(sessions.borrow()[&handle].options.helpcode_schema, "xiaohe");
        assert!(!sessions.borrow()[&handle].options.show_helpcode);
    });
    preferences.scheme = InputScheme::Shuangpin;
    assert_eq!(update(handle, 2, &preferences)["value"]["deferred"], false);
    SESSIONS.with(|sessions| {
        assert!(sessions.borrow()[&handle].options.helpcode);
        assert!(sessions.borrow()[&handle].options.show_helpcode);
        assert_eq!(
            sessions.borrow()[&handle].options.helpcode_schema,
            "shouyou2_0"
        );
    });
    preferences.scheme = InputScheme::Quanpin;
    update(handle, 3, &preferences);
    SESSIONS.with(|sessions| assert!(!sessions.borrow()[&handle].options.helpcode));
    read(msime_client_destroy(handle));
}

#[test]
fn autocorrect_update_waits_for_composition_end() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    let before = read(msime_client_view(handle))["value"].clone();
    let preferences = Preferences {
        quanpin: msime_client_core::preferences::QuanpinPreferences {
            autocorrect_transposition: Some(true),
            autocorrect_neighbor: Some(true),
        },
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
    assert_eq!(read(msime_client_view(handle))["value"], before);
    SESSIONS.with(|sessions| {
        assert!(!sessions.borrow()[&handle].options.autocorrect_transposition);
        assert!(!sessions.borrow()[&handle].options.autocorrect_neighbor);
    });
    read(msime_client_command(handle, 3));
    SESSIONS.with(|sessions| {
        assert!(sessions.borrow()[&handle].options.autocorrect_transposition);
        assert!(sessions.borrow()[&handle].options.autocorrect_neighbor);
    });
    assert_eq!(
        update(handle, 2, &Preferences::default())["value"]["deferred"],
        false
    );
    SESSIONS.with(|sessions| {
        assert!(!sessions.borrow()[&handle].options.autocorrect_transposition);
        assert!(!sessions.borrow()[&handle].options.autocorrect_neighbor);
    });
    read(msime_client_destroy(handle));
}

#[test]
#[cfg(not(target_os = "android"))]
fn skin_catalog_reaches_native_presenters_without_the_settings_shell() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("skins");
    let scan = |path: &str| read(unsafe { msime_client_skin_catalog(path.as_ptr(), path.len()) });
    let path = root.to_str().unwrap().to_owned();
    // An absent root is an empty catalog, not a failure the presenter shows.
    assert_eq!(
        scan(&path),
        json!({"ok": true, "value": {"packages": [], "issues": []}})
    );
    std::fs::create_dir_all(root.join("sample")).unwrap();
    std::fs::write(
        root.join("sample/skin.toml"),
        "schema_version = 1\nid = 'sample'\nname = 'Sample'\nversion = '1.0'\n\
         base = 'fluent'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n\
         [candidate_window]\nmin_width_dip = 10\n[candidate_window.decoration]\n\
         top_inset_dip = 0\nwidth_dip = 0\n",
    )
    .unwrap();
    std::fs::create_dir_all(root.join("broken")).unwrap();
    std::fs::write(root.join("broken/skin.toml"), "not a manifest").unwrap();
    let catalog = scan(&path);
    assert_eq!(catalog["ok"], true);
    assert_eq!(catalog["value"]["packages"][0]["id"], "sample");
    assert_eq!(catalog["value"]["packages"][0]["minWidthDip"], 10.0);
    assert_eq!(catalog["value"]["packages"][0]["layouts"][0], "vertical");
    assert_eq!(catalog["value"]["packages"].as_array().unwrap().len(), 1);
    // A package that fails validation is reported, never offered for rendering.
    assert_eq!(catalog["value"]["issues"][0]["folder"], "broken");
    assert_eq!(
        catalog["value"],
        serde_json::to_value(msime_client_core::skin::catalog::scan(&root)).unwrap()
    );
    let relative = "skins";
    assert_eq!(scan(relative)["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_skin_catalog(std::ptr::null(), 0) })["ok"],
        false
    );
}

#[test]
#[cfg(not(target_os = "android"))]
fn skin_resource_bridge_revalidates_kind_and_package_containment() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("skins");
    let skin = root.join("sample");
    std::fs::create_dir_all(skin.join("images")).unwrap();
    std::fs::write(
        skin.join("skin.toml"),
        "schema_version = 1\nid = 'sample'\nname = 'Sample'\nversion = '1.0'\n\
         base = 'fluent'\ntoolbar_stylesheet = 'toolbar.css'\npreview = 'images/preview.png'\n\
         [supports]\nlayouts = ['vertical']\nthemes = ['dark']\n\
         [candidate_window]\nmin_width_dip = 10\n\
         [candidate_window.decoration]\ntop_inset_dip = 1\nwidth_dip = 10\n",
    )
    .unwrap();
    std::fs::write(skin.join("images/preview.png"), [1_u8, 2, 3]).unwrap();
    std::fs::write(skin.join("font.woff2"), [4_u8, 5, 6]).unwrap();
    std::fs::write(skin.join("toolbar.css"), ".sample { color: red; }").unwrap();
    let directory = root.to_str().unwrap().to_owned();
    let call = |request: Value| {
        let document = request.to_string();
        read(unsafe { msime_client_skin_resource(document.as_ptr(), document.len()) })
    };
    let image = call(json!({
        "directory": directory,
        "id": "sample",
        "relative": "images/preview.png",
        "kind": "image"
    }));
    assert_eq!(image["ok"], true);
    assert_eq!(image["value"]["contentType"], "image/png");
    assert_eq!(image["value"]["bytes"], json!([1, 2, 3]));
    let font = call(json!({
        "directory": root.to_str().unwrap(),
        "id": "sample",
        "relative": "font.woff2",
        "kind": "font"
    }));
    assert_eq!(font["ok"], true);
    assert_eq!(font["value"]["contentType"], "font/woff2");
    let mismatch = call(json!({
        "directory": root.to_str().unwrap(),
        "id": "sample",
        "relative": "toolbar.css",
        "kind": "image"
    }));
    assert_eq!(mismatch["ok"], false);
    let escaped = call(json!({
        "directory": root.to_str().unwrap(),
        "id": "sample",
        "relative": "../toolbar.css",
        "kind": "image"
    }));
    assert_eq!(escaped["ok"], false);
    let stylesheet_request = json!({
        "directory": root.to_str().unwrap(),
        "id": "sample"
    });
    let stylesheet_document = stylesheet_request.to_string();
    let stylesheet = read(unsafe {
        msime_client_skin_toolbar_stylesheet(
            stylesheet_document.as_ptr(),
            stylesheet_document.len(),
        )
    });
    assert_eq!(
        stylesheet,
        json!({"ok": true, "value": ".sample { color: red; }"})
    );
    let invalid = read(unsafe { msime_client_skin_resource(std::ptr::null(), 0) });
    assert_eq!(invalid["ok"], false);
}
#[test]
#[cfg(not(target_os = "android"))]
fn try_preferences_reader_reports_contention_without_defaults() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().to_str().unwrap();
    let load = || read(unsafe { msime_client_try_load_preferences(path.as_ptr(), path.len()) });
    let initial = load();
    assert_eq!(initial["ok"], true);
    assert_eq!(initial["value"]["revision"], 0);
    let lock = std::fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(directory.path().join("preferences.lock"))
        .unwrap();
    lock.lock().unwrap();
    assert_eq!(load(), json!({"ok": true, "value": null}));
    drop(lock);
    assert_eq!(load(), initial);
    std::fs::write(directory.path().join("preferences.json"), "broken").unwrap();
    assert_eq!(load()["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_try_load_preferences(std::ptr::null(), 0) })["ok"],
        false
    );
}

#[test]
#[cfg(not(target_os = "android"))]
fn save_preferences_uses_compare_and_swap_and_rejects_invalid_snapshots() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().to_string_lossy().into_owned();
    let snapshot = serde_json::to_string(&PreferencesSnapshot::default()).unwrap();
    let save = |revision, document: &str| {
        read(unsafe {
            msime_client_save_preferences(
                path.as_ptr(),
                path.len(),
                revision,
                document.as_ptr(),
                document.len(),
            )
        })
    };

    let saved = save(0, &snapshot);
    assert_eq!(saved["ok"], true);
    assert_eq!(saved["value"]["revision"], 1);
    let file = directory.path().join("preferences.json");
    let original = std::fs::read_to_string(&file).unwrap();

    let conflict = save(0, &snapshot);
    assert_eq!(conflict["ok"], false);
    assert!(conflict["error"].as_str().unwrap().contains("changed"));
    assert_eq!(std::fs::read_to_string(&file).unwrap(), original);

    let mut invalid = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
    invalid["format_version"] = json!(2);
    let invalid = invalid.to_string();
    let rejected = save(1, &invalid);
    assert_eq!(rejected["ok"], false);
    assert!(rejected["error"].as_str().unwrap().contains("unsupported"));
    assert_eq!(std::fs::read_to_string(file).unwrap(), original);
}
#[test]
fn background_preferences_reader_uses_shared_store_and_preserves_bad_files() {
    let directory = tempfile::tempdir().unwrap();
    let saved = PreferencesStore::new(directory.path())
        .save(0, Preferences::default())
        .unwrap();
    let path = directory.path().to_str().unwrap().to_owned();
    let load = |path: String| {
        std::thread::spawn(move || {
            read(unsafe { msime_client_load_preferences(path.as_ptr(), path.len()) })
        })
        .join()
        .unwrap()
    };
    assert_eq!(
        load(path.clone())["value"],
        serde_json::to_value(saved).unwrap()
    );
    let file = directory.path().join("preferences.json");
    std::fs::write(&file, "broken").unwrap();
    assert_eq!(load(path)["ok"], false);
    assert_eq!(std::fs::read_to_string(file).unwrap(), "broken");
    assert_eq!(load("relative".into())["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_load_preferences(std::ptr::null(), 0) })["ok"],
        false
    );
}
#[test]
fn typing_statistics_boundary_persists_only_aggregate_counts() {
    let directory = tempfile::tempdir().unwrap();
    let call = |action: Value| {
        let request = serde_json::to_vec(&json!({
            "directory": directory.path(),
            "action": action,
        }))
        .unwrap();
        read(unsafe { msime_client_typing_statistics(request.as_ptr(), request.len()) })
    };
    let recorded = call(json!({
        "operation": "record",
        "text": "synthetic 🌲",
        "source": "handwriting",
        "day": "2026-09-12",
    }));
    assert_eq!(recorded["value"]["recorded"], 10);
    let loaded = call(json!({"operation": "load"}));
    assert_eq!(loaded["value"]["total"], 10);
    assert_eq!(loaded["value"]["detail"]["characters"]["latin"], 9);
    assert_eq!(loaded["value"]["detail"]["characters"]["emoji"], 1);
    assert_eq!(loaded["value"]["detail"]["sources"]["handwriting"], 10);
    let persisted =
        std::fs::read_to_string(directory.path().join("typing-statistics.json")).unwrap();
    assert!(!persisted.contains("synthetic"));
    assert_eq!(
        call(json!({"operation": "set_enabled", "enabled": false}))["value"]["enabled"],
        false
    );
    assert_eq!(
        call(json!({
            "operation": "record",
            "text": "ignored",
            "source": "english",
            "day": "2026-09-12",
        }))["value"]["recorded"],
        0
    );
    let reset = call(json!({"operation": "reset"}));
    assert_eq!(reset["value"]["total"], 0);
    assert_eq!(reset["value"]["enabled"], false);
    assert_eq!(
        read(unsafe { msime_client_typing_statistics(std::ptr::null(), 0) })["ok"],
        false
    );
}
#[test]
fn clipboard_reader_respects_preferences_and_preserves_history() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().to_str().unwrap();
    let load = || read(unsafe { msime_client_load_clipboard_history(path.as_ptr(), path.len()) });
    let store = PreferencesStore::new(directory.path());
    let saved = store
        .save(
            0,
            Preferences {
                clipboard_history: true,
                ..Preferences::default()
            },
        )
        .unwrap();
    assert_eq!(load()["value"]["entries"], serde_json::json!([]));
    let file = directory.path().join("clipboard_history.json");
    let fixture = r#"["synthetic alpha","synthetic beta","synthetic alpha"]"#;
    std::fs::write(&file, fixture).unwrap();
    assert_eq!(
        load()["value"]["entries"],
        serde_json::json!(["synthetic alpha", "synthetic beta"])
    );
    assert_eq!(std::fs::read_to_string(&file).unwrap(), fixture);
    std::fs::write(&file, "broken synthetic fixture").unwrap();
    assert_eq!(load()["error"], "clipboard history unavailable");
    let mut preferences = saved.preferences;
    preferences.clipboard_history = false;
    store.save(saved.revision, preferences).unwrap();
    assert_eq!(
        load()["value"],
        serde_json::json!({"enabled": false, "entries": []})
    );
    assert_eq!(
        std::fs::read_to_string(&file).unwrap(),
        "broken synthetic fixture"
    );
    std::fs::write(directory.path().join("preferences.json"), "broken").unwrap();
    assert_eq!(load()["error"], "history preferences unavailable");
    assert_eq!(
        read(unsafe { msime_client_load_clipboard_history(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_load_clipboard_history(b"relative".as_ptr(), 8) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_load_clipboard_history([255u8].as_ptr(), 1) })["ok"],
        false
    );
}

#[test]
fn mobile_clipboard_migrates_apple_history_and_uses_structured_actions() {
    let directory = tempfile::tempdir().unwrap();
    let call = |action: Value| {
        let request = serde_json::to_vec(&json!({
            "directory": directory.path(),
            "action": action,
        }))
        .unwrap();
        read(unsafe { msime_client_mobile_clipboard_history(request.as_ptr(), request.len()) })
    };
    let legacy = directory.path().join("Clipboard/history.json");
    std::fs::create_dir_all(legacy.parent().unwrap()).unwrap();
    std::fs::write(
        &legacy,
        serde_json::to_vec(&json!([
            {
                "id": "00000000-0000-4000-8000-000000000001",
                "text": "synthetic older",
                "date": 721_692_800.0,
                "pinned": false
            },
            {
                "id": "00000000-0000-4000-8000-000000000002",
                "text": "synthetic pinned",
                "date": 721_692_900.0,
                "pinned": true
            }
        ]))
        .unwrap(),
    )
    .unwrap();

    let loaded = call(json!({"operation": "load"}));
    assert_eq!(loaded["value"]["migrated"], true);
    assert_eq!(loaded["value"]["entries"][0]["text"], "synthetic pinned");
    assert_eq!(
        loaded["value"]["entries"][0]["timestampMs"],
        1_700_000_100_000_u64
    );
    assert_eq!(loaded["value"]["entries"][1]["text"], "synthetic older");
    assert!(!legacy.exists());
    assert!(directory
        .path()
        .join("MSIME/clipboard_history.json")
        .exists());
    assert!(!directory.path().join("preferences.json").exists());
    assert_eq!(
        call(json!({"operation": "load"}))["value"]["migrated"],
        false
    );

    assert_eq!(
        call(json!({"operation": "capture", "text": "synthetic current"}))["value"]["captured"],
        true
    );
    assert_eq!(
        call(json!({
            "operation": "set_pinned",
            "text": "synthetic current",
            "pinned": true
        }))["value"]["updated"],
        true
    );
    let pinned = call(json!({"operation": "load"}));
    assert_eq!(pinned["value"]["entries"][0]["text"], "synthetic current");
    assert_eq!(pinned["value"]["entries"][1]["text"], "synthetic pinned");
    assert_eq!(
        call(json!({"operation": "remove", "text": "synthetic older"}))["value"]["removed"],
        true
    );
    assert_eq!(
        call(json!({"operation": "clear"}))["value"]["cleared"],
        true
    );
    assert_eq!(
        call(json!({"operation": "load"}))["value"]["entries"],
        json!([])
    );
}

#[test]
fn mobile_clipboard_preserves_invalid_legacy_and_existing_shared_history() {
    let invalid = tempfile::tempdir().unwrap();
    let legacy = invalid.path().join("Clipboard/history.json");
    std::fs::create_dir_all(legacy.parent().unwrap()).unwrap();
    let fixture = b"invalid synthetic legacy";
    std::fs::write(&legacy, fixture).unwrap();
    let request = serde_json::to_vec(&json!({
        "directory": invalid.path(),
        "action": {"operation": "load"}
    }))
    .unwrap();
    let response =
        read(unsafe { msime_client_mobile_clipboard_history(request.as_ptr(), request.len()) });
    assert_eq!(response["error"], "invalid legacy clipboard history");
    assert_eq!(std::fs::read(&legacy).unwrap(), fixture);
    assert!(!invalid.path().join("MSIME/clipboard_history.json").exists());

    let existing = tempfile::tempdir().unwrap();
    let call = |action: Value| {
        let request = serde_json::to_vec(&json!({
            "directory": existing.path(),
            "action": action,
        }))
        .unwrap();
        read(unsafe { msime_client_mobile_clipboard_history(request.as_ptr(), request.len()) })
    };
    assert_eq!(
        call(json!({"operation": "capture", "text": "synthetic shared"}))["value"]["captured"],
        true
    );
    let legacy = existing.path().join("Clipboard/history.json");
    std::fs::create_dir_all(legacy.parent().unwrap()).unwrap();
    std::fs::write(&legacy, b"invalid synthetic legacy").unwrap();
    let loaded = call(json!({"operation": "load"}));
    assert_eq!(loaded["value"]["entries"][0]["text"], "synthetic shared");
    assert!(legacy.exists());
    assert_eq!(
        call(json!({"operation": "clear"}))["value"]["cleared"],
        true
    );
    assert!(!legacy.exists());
    assert_eq!(
        call(json!({"operation": "load"}))["value"]["entries"],
        json!([])
    );

    let null = read(unsafe { msime_client_mobile_clipboard_history(std::ptr::null(), 0) });
    assert_eq!(null["ok"], false);
    let relative = serde_json::to_vec(&json!({
        "directory": "relative",
        "action": {"operation": "load"}
    }))
    .unwrap();
    assert_eq!(
        read(unsafe { msime_client_mobile_clipboard_history(relative.as_ptr(), relative.len()) })
            ["ok"],
        false
    );
}

#[test]
fn history_removal_is_exact_idempotent_and_respects_disabled_setting() {
    let directory = tempfile::tempdir().unwrap();
    let file = directory.path().join("clipboard_history.json");
    let store = PreferencesStore::new(directory.path());
    let saved = store
        .save(
            0,
            Preferences {
                clipboard_history: true,
                ..Preferences::default()
            },
        )
        .unwrap();
    let remove = |path: &std::path::Path, text: &str| {
        let request = serde_json::to_vec(&json!({"directory": path, "text": text})).unwrap();
        read(unsafe { msime_client_remove_clipboard_history(request.as_ptr(), request.len()) })
    };
    std::fs::write(&file, br#"["synthetic first","synthetic second"]"#).unwrap();
    assert_eq!(
        remove(directory.path(), "synthetic first")["value"]["removed"],
        true
    );
    let upgraded: Vec<msime_client_core::clipboard::ClipboardHistoryEntry> =
        serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    assert_eq!(upgraded.len(), 1);
    assert_eq!(upgraded[0].text, "synthetic second");
    assert_eq!(
        remove(directory.path(), "synthetic first")["value"]["removed"],
        false
    );
    assert_eq!(remove(directory.path(), "")["ok"], false);
    assert_eq!(
        remove(std::path::Path::new("relative"), "synthetic")["ok"],
        false
    );
    let maximum = msime_client_core::clipboard::MAX_TEXT_BYTES;
    assert_eq!(remove(directory.path(), &"x".repeat(maximum))["ok"], true);
    assert_eq!(
        remove(directory.path(), &"x".repeat(maximum + 1))["ok"],
        false
    );
    let mut preferences = saved.preferences;
    preferences.clipboard_history = false;
    store.save(saved.revision, preferences).unwrap();
    assert_eq!(
        remove(directory.path(), "synthetic second")["error"],
        "clipboard history disabled"
    );
    let preserved: Vec<msime_client_core::clipboard::ClipboardHistoryEntry> =
        serde_json::from_slice(&std::fs::read(&file).unwrap()).unwrap();
    assert_eq!(preserved, upgraded);
    assert_eq!(
        read(unsafe { msime_client_remove_clipboard_history(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_remove_clipboard_history(b"{".as_ptr(), 1) })["ok"],
        false
    );
}

#[test]
fn history_capture_bridge_validates_and_returns_no_text() {
    let directory = tempfile::tempdir().unwrap();
    let capture = |request: Value| {
        let bytes = serde_json::to_vec(&request).unwrap();
        read(unsafe { msime_client_capture_clipboard_history(bytes.as_ptr(), bytes.len()) })
    };
    let request = json!({"directory": directory.path(), "text": "synthetic capture"});
    assert_eq!(
        capture(request.clone())["value"],
        json!({"captured": false})
    );
    assert!(!directory.path().join("clipboard_history.json").exists());
    PreferencesStore::new(directory.path())
        .save(
            0,
            Preferences {
                clipboard_history: true,
                ..Preferences::default()
            },
        )
        .unwrap();
    assert_eq!(capture(request.clone())["value"], json!({"captured": true}));
    assert_eq!(
        capture(json!({"directory": "relative", "text": "synthetic"}))["ok"],
        false
    );
    let maximum = msime_client_core::clipboard::MAX_TEXT_BYTES;
    assert_eq!(
        capture(json!({"directory": directory.path(), "text": "x".repeat(maximum)}))["ok"],
        true
    );
    assert_eq!(
        capture(json!({"directory": directory.path(), "text": "x".repeat(maximum + 1)}))["ok"],
        false
    );
    assert_eq!(capture(json!({"directory": directory.path()}))["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_capture_clipboard_history(std::ptr::null(), 0) })["ok"],
        false
    );
    std::fs::write(directory.path().join("preferences.json"), "broken").unwrap();
    assert_eq!(
        capture(request)["error"],
        "clipboard history capture failed"
    );
}

fn test_host(root: &std::path::Path) -> u64 {
    test_host_preferences(root, chinese_preferences())
}
fn chinese_preferences() -> Preferences {
    Preferences {
        default_ime_mode: msime_client_core::preferences::DefaultImeMode::Chinese,
        ..Preferences::default()
    }
}
fn test_host_preferences(root: &std::path::Path, preferences: Preferences) -> u64 {
    let path = |name| {
        let path = root.join(name);
        std::fs::create_dir_all(&path).unwrap();
        path
    };
    let options = json!({ "api_version": 1, "resources": path("resources"), "user_data": path("user"), "cache": path("cache"), "dictionaries": path("dictionaries"), "preferences": preferences }).to_string();
    let created = read(unsafe { msime_client_create(options.as_ptr(), options.len()) });
    assert_eq!(created["ok"], true);
    created["value"]["session"].as_u64().unwrap()
}
fn test_host_with_pinyin_fixture(root: &std::path::Path, preferences: Preferences) -> u64 {
    let path = |name| {
        let path = root.join(name);
        std::fs::create_dir_all(&path).unwrap();
        path
    };
    let resources = path("resources");
    let dictionaries = path("dictionaries");
    let fixture = "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);
                   INSERT INTO tbl_2_n VALUES('ni''hao','nh','本地',100),('ni''hao','nh','拟好',80);
                   CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);
                   CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER);
                   CREATE INDEX idx_quick_parases_key_weight ON quick_parases(key,weight DESC);";
    for directory in [&resources, &dictionaries] {
        rusqlite::Connection::open(directory.join("msime.db"))
            .unwrap()
            .execute_batch(fixture)
            .unwrap();
    }
    let options = json!({ "api_version": 1, "resources": resources, "user_data": path("user"), "cache": path("cache"), "dictionaries": dictionaries, "preferences": preferences }).to_string();
    let created = read(unsafe { msime_client_create(options.as_ptr(), options.len()) });
    assert_eq!(created["ok"], true);
    created["value"]["session"].as_u64().unwrap()
}
fn update(handle: u64, revision: u64, preferences: &Preferences) -> Value {
    let snapshot = json!({ "format_version": 1, "revision": revision, "preferences": preferences })
        .to_string();
    read(unsafe { msime_client_update_preferences(handle, snapshot.as_ptr(), snapshot.len()) })
}

#[test]
fn translation_queries_use_latest_preferences_without_resetting_composition() {
    let dir = tempfile::tempdir().unwrap();
    let mut preferences = Preferences {
        candidate_translations: false,
        ..Preferences::default()
    };
    let handle = test_host_preferences(dir.path(), preferences.clone());
    read(msime_client_focus(handle, true));
    let mut view = Value::Null;
    for byte in b"U4e2d" {
        view = read(msime_client_character(
            handle,
            *byte,
            byte.is_ascii_uppercase(),
        ))["value"]["view"]
            .clone();
    }
    assert!(!view["candidates"].as_array().unwrap().is_empty());
    assert_eq!(
        read(msime_client_translation_query(handle))["value"],
        Value::Null
    );
    preferences.candidate_translations = true;
    preferences.translation_target_language =
        msime_client_core::preferences::TranslationTargetLanguage::Fr;
    preferences.translation_secondary_language =
        Some(msime_client_core::preferences::TranslationTargetLanguage::Ja);
    preferences.custom_translation.enabled = true;
    preferences.custom_translation.endpoint = "https://translation.example.invalid".into();
    preferences.tencent_tmt.secret_id = "AKIDsynthetic".into();
    preferences.tencent_tmt.secret_key = "synthetic".into();
    let changed = update(handle, 1, &preferences);
    assert_eq!(changed["value"]["deferred"], true);
    assert_eq!(changed["value"]["view"]["generation"], view["generation"]);
    let query = read(msime_client_translation_query(handle));
    assert_eq!(query["value"]["generation"], view["generation"]);
    assert_eq!(query["value"]["target_language"], "fr");
    assert_eq!(query["value"]["target_languages"], json!(["fr", "ja"]));
    assert!(query["value"]["user_data"].is_null());
    assert_eq!(
        query["value"]["custom_translation"]["endpoint"],
        "https://translation.example.invalid"
    );
    assert!(!query["value"]["candidates"].as_array().unwrap().is_empty());
    assert!(query["value"]["tencent_tmt"].is_null());
    preferences.custom_translation.enabled = false;
    update(handle, 2, &preferences);
    let tencent_query = read(msime_client_translation_query(handle));
    assert_eq!(tencent_query["value"]["generation"], view["generation"]);
    assert_eq!(
        tencent_query["value"]["tencent_tmt"]["region"],
        "ap-guangzhou"
    );
    assert_eq!(
        tencent_query["value"]["tencent_tmt"]["secret_id"],
        "AKIDsynthetic"
    );
    preferences.tencent_tmt.enabled = false;
    update(handle, 3, &preferences);
    assert!(read(msime_client_translation_query(handle))["value"]["tencent_tmt"].is_null());
    preferences.tencent_tmt.enabled = true;
    preferences.tencent_tmt.secret_key.clear();
    update(handle, 4, &preferences);
    assert!(read(msime_client_translation_query(handle))["value"]["tencent_tmt"].is_null());
    preferences.candidate_translations = false;
    update(handle, 5, &preferences);
    assert_eq!(
        read(msime_client_translation_query(handle))["value"],
        Value::Null
    );

    // The offline gloss is a packaged dictionary lookup, so it has to be
    // reachable with every online provider off - which is the usual case,
    // and was why Windows could not offer the setting at all.
    preferences.candidate_english_gloss = true;
    preferences.translation_target_language =
        msime_client_core::preferences::TranslationTargetLanguage::En;
    update(handle, 6, &preferences);
    let gloss = read(msime_client_translation_query(handle));
    assert_eq!(gloss["value"]["generation"], view["generation"]);
    assert_eq!(gloss["value"]["english_gloss"], true);
    assert_eq!(gloss["value"]["target_language"], "en");
    // The dictionary paths ride along only because the lookup needs them.
    assert!(gloss["value"]["resources"].is_string());
    assert!(!gloss["value"]["candidates"].as_array().unwrap().is_empty());
    // Still no online provider: the gloss must not imply one.
    assert!(gloss["value"]["tencent_tmt"].is_null());
    assert!(gloss["value"]["custom_translation"].is_null());
    assert!(gloss["value"]["niutrans"].is_null());

    // The packaged gloss dictionary is English only, so another target
    // language is an online request or nothing - never a wrong-language
    // gloss.
    preferences.translation_target_language =
        msime_client_core::preferences::TranslationTargetLanguage::Ja;
    update(handle, 7, &preferences);
    assert_eq!(
        read(msime_client_translation_query(handle))["value"],
        Value::Null
    );

    // An English secondary language still enables the packaged offline
    // dictionary while preserving the user's primary target.
    preferences.translation_secondary_language =
        Some(msime_client_core::preferences::TranslationTargetLanguage::En);
    preferences.candidate_english_gloss = true;
    update(handle, 8, &preferences);
    let secondary_gloss = read(msime_client_translation_query(handle));
    assert_eq!(
        secondary_gloss["value"]["target_languages"],
        json!(["ja", "en"])
    );
    assert_eq!(secondary_gloss["value"]["english_gloss"], true);

    // With the gloss off, only the user path needed to persist successful
    // English-target provider results is carried. Packaged resources stay
    // private to offline lookup.
    preferences.candidate_english_gloss = false;
    preferences.translation_target_language =
        msime_client_core::preferences::TranslationTargetLanguage::En;
    preferences.candidate_translations = true;
    preferences.tencent_tmt.secret_key = "synthetic".into();
    update(handle, 9, &preferences);
    let online = read(msime_client_translation_query(handle));
    assert_eq!(online["value"]["english_gloss"], false);
    assert!(online["value"]["resources"].is_null());
    assert!(online["value"]["user_data"].is_string());
    read(msime_client_destroy(handle));
}

#[test]
fn translation_results_reject_control_characters_atomically() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    let mut view = Value::Null;
    for byte in b"U4e2d" {
        view = read(msime_client_character(
            handle,
            *byte,
            byte.is_ascii_uppercase(),
        ))["value"]["view"]
            .clone();
    }
    let generation = view["generation"].as_u64().unwrap();
    let candidate = view["candidates"][0]["text"].as_str().unwrap().to_owned();
    let apply = |values: Value| {
        let encoded = serde_json::to_vec(&values).unwrap();
        read(unsafe {
            msime_client_apply_translations(handle, generation, encoded.as_ptr(), encoded.len())
        })
    };

    let applied = apply(json!([{"text":candidate,"translation":"合成释义"}]));
    assert_eq!(applied["ok"], true);
    assert_eq!(applied["value"]["applied"], true);
    assert_eq!(
        applied["value"]["view"]["candidates"][0]["translation"],
        "合成释义"
    );
    let before = applied["value"]["view"].clone();

    for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
        let control = char::from_u32(codepoint).unwrap();
        for invalid in [
            json!([{"text":format!("{candidate}{control}"),"translation":"safe"}]),
            json!([{"text":candidate,"translation":format!("before{control}after")}]),
        ] {
            let rejected = apply(invalid);
            assert_eq!(rejected["ok"], false);
            assert_eq!(rejected["error"], "translation entries exceed limits");
        }
    }
    assert_eq!(read(msime_client_view(handle))["value"], before);
    read(msime_client_destroy(handle));
}

#[test]
fn translation_queries_follow_active_japanese_mode() {
    for temporary in [false, true] {
        let dir = tempfile::tempdir().unwrap();
        if temporary {
            // The host disables the temporary Japanese shortcut when its
            // model resource is absent.  This test supplies a bounded
            // placeholder so it exercises the shortcut's generated kana
            // path without depending on a packaged model.
            std::fs::create_dir_all(dir.path().join("resources")).unwrap();
            std::fs::write(dir.path().join("resources/dict_japanese.dat"), b"synthetic").unwrap();
        }
        let preferences = Preferences {
            scheme: if temporary {
                InputScheme::Quanpin
            } else {
                InputScheme::Japanese
            },
            candidate_translations: true,
            ..chinese_preferences()
        };
        let handle = test_host_preferences(dir.path(), preferences.clone());
        read(msime_client_focus(handle, true));
        if temporary {
            read(msime_client_character(handle, b'R', true));
        }
        let view = read(msime_client_character(handle, b'a', false))["value"]["view"].clone();
        assert!(!view["candidates"].as_array().unwrap().is_empty());
        assert_eq!(view["local_mode"] == "temporary_japanese", temporary);
        assert_eq!(
            read(msime_client_translation_query(handle))["value"],
            Value::Null
        );
        read(msime_client_command(handle, 3));
        update(
            handle,
            1,
            &Preferences {
                scheme: InputScheme::Quanpin,
                ..preferences
            },
        );
        for byte in b"U4e2d" {
            read(msime_client_character(
                handle,
                *byte,
                byte.is_ascii_uppercase(),
            ));
        }
        let query = read(msime_client_translation_query(handle));
        assert!(query["value"]["candidates"]
            .as_array()
            .is_some_and(|items| !items.is_empty()));
        read(msime_client_destroy(handle));
    }
}

#[test]
fn shuangpin_preedit_mode_is_applied_after_composition() {
    let dir = tempfile::tempdir().unwrap();
    let raw = Preferences {
        scheme: InputScheme::Shuangpin,
        ..chinese_preferences()
    };
    let handle = test_host_preferences(dir.path(), raw.clone());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'h', false));
    let before = read(msime_client_character(handle, b'k', false))["value"]["view"].clone();
    let expanded = Preferences {
        shuangpin_preedit_uses_raw: false,
        ..raw.clone()
    };
    let queued = update(handle, 1, &expanded);
    assert_eq!(queued["value"]["deferred"], true);
    assert_eq!(queued["value"]["view"], before);
    read(msime_client_command(handle, 3));
    assert_eq!(update(handle, 1, &expanded)["value"]["deferred"], false);
    read(msime_client_character(handle, b'h', false));
    let after = read(msime_client_character(handle, b'k', false))["value"]["view"].clone();
    assert_eq!(after["editing_text"], before["editing_text"]);
    assert_ne!(after["preedit"], before["preedit"]);
    read(msime_client_command(handle, 3));
    update(handle, 2, &raw);
    read(msime_client_character(handle, b'h', false));
    let restored = read(msime_client_character(handle, b'k', false));
    assert_eq!(restored["value"]["view"]["preedit"], before["preedit"]);
    msime_client_destroy(handle);
}

#[test]
fn shuangpin_profile_creation_and_deferred_replacement_use_real_engine() {
    let dir = tempfile::tempdir().unwrap();
    let microsoft = Preferences {
        scheme: InputScheme::Shuangpin,
        shuangpin_profile: ShuangpinProfile::Microsoft,
        ..chinese_preferences()
    };
    let handle = test_host_preferences(dir.path(), microsoft.clone());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'b', false));
    let first = read(msime_client_character(handle, b';', false));
    assert_eq!(first["value"]["view"]["editing_text"], "b;");
    let xiaohe = Preferences {
        shuangpin_profile: ShuangpinProfile::Xiaohe,
        ..microsoft.clone()
    };
    let before = read(msime_client_view(handle))["value"].clone();
    let queued = update(handle, 1, &xiaohe);
    assert_eq!(before["microsoft_shuangpin"], true);
    assert_eq!(before["shuangpin_profile"], "microsoft");
    assert_eq!(queued["value"]["deferred"], true);
    assert_eq!(queued["value"]["view"], before);
    // The old composition completes under Microsoft before replacing Engine.
    assert_eq!(
        read(msime_client_command(handle, 2))["value"]["commit"],
        "b;"
    );
    assert_eq!(update(handle, 1, &xiaohe)["value"]["deferred"], false);
    assert_eq!(
        read(msime_client_view(handle))["value"]["shuangpin_profile"],
        "xiaohe"
    );
    assert_eq!(
        read(msime_client_view(handle))["value"]["microsoft_shuangpin"],
        false
    );
    read(msime_client_character(handle, b'b', false));
    let replaced = read(msime_client_character(handle, b';', false));
    assert_ne!(replaced["value"]["view"]["editing_text"], "b;");
    read(msime_client_command(handle, 3));
    assert_eq!(update(handle, 2, &microsoft)["value"]["deferred"], false);
    read(msime_client_character(handle, b'b', false));
    assert_eq!(
        read(msime_client_character(handle, b';', false))["value"]["view"]["editing_text"],
        "b;"
    );
    read(msime_client_destroy(handle));
}
#[test]
fn explicit_punctuation_finishes_unicode_and_rejects_invalid_bytes() {
    for enabled in [true, false] {
        let dir = tempfile::tempdir().unwrap();
        let handle = test_host(dir.path());
        assert_eq!(read(msime_client_focus(handle, true))["ok"], true);
        read(msime_client_set_chinese_punctuation(handle, enabled));
        read(msime_client_character(handle, b'U', true));
        for byte in b"4e2d" {
            read(msime_client_character(handle, *byte, false));
        }
        let before = read(msime_client_view(handle));
        for invalid in [b'a', b' ', 0, 128, 255] {
            assert_eq!(read(msime_client_punctuation(handle, invalid))["ok"], false);
            assert_eq!(read(msime_client_view(handle)), before);
        }
        assert_eq!(
            std::thread::spawn(move || read(msime_client_punctuation(handle, b','))["ok"].clone())
                .join()
                .unwrap(),
            false
        );
        assert_eq!(read(msime_client_view(handle)), before);
        let result = read(msime_client_punctuation(handle, b','));
        assert_eq!(result["ok"], true);
        assert_eq!(result["value"]["handled"], true);
        assert_eq!(
            result["value"]["commit"],
            if enabled { "中，" } else { "中," }
        );
        assert_eq!(result["value"]["view"]["editing_text"], "");
        read(msime_client_destroy(handle));
        assert_eq!(read(msime_client_punctuation(handle, b','))["ok"], false);
    }
}

#[test]
fn contextual_punctuation_respects_editor_context_preferences_and_composition() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    assert_eq!(read(msime_client_focus(handle, true))["ok"], true);

    for preceding in [u32::from('0'), u32::from('a'), u32::from('Z')] {
        for punctuation in *b",.:" {
            let result = read(msime_client_punctuation_with_context(
                handle,
                punctuation,
                preceding,
            ));
            assert_eq!(result["ok"], true);
            assert_eq!(result["value"]["handled"], false);
        }
    }
    for preceding in [0, u32::from('中'), u32::from(' ')] {
        let result = read(msime_client_punctuation_with_context(
            handle, b',', preceding,
        ));
        assert_eq!(result["value"]["commit"], "，");
    }
    assert_eq!(
        read(msime_client_punctuation_with_context(
            handle,
            b'?',
            u32::from('a')
        ))["value"]["commit"],
        "？"
    );

    read(msime_client_set_punctuation_lock(handle, 1));
    assert_eq!(
        read(msime_client_punctuation_with_context(
            handle,
            b',',
            u32::from('a')
        ))["value"]["commit"],
        "，"
    );
    read(msime_client_set_punctuation_lock(handle, 2));
    assert_eq!(
        read(msime_client_punctuation_with_context(
            handle,
            b',',
            u32::from('中')
        ))["value"]["handled"],
        false
    );
    read(msime_client_set_punctuation_lock(handle, 0));

    read(msime_client_character(handle, b'n', false));
    read(msime_client_character(handle, b'i', false));
    let composed = read(msime_client_punctuation_with_context(
        handle,
        b',',
        u32::from('a'),
    ));
    assert!(composed["value"]["commit"]
        .as_str()
        .is_some_and(|value| value.ends_with('，')));

    let preferences = Preferences {
        smart_punctuation: false,
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], false);
    assert_eq!(
        read(msime_client_punctuation_with_context(
            handle,
            b'.',
            u32::from('7')
        ))["value"]["commit"],
        "。"
    );
    assert_eq!(
        read(msime_client_punctuation_with_context(
            handle,
            b'a',
            u32::from('7')
        ))["ok"],
        false
    );
    assert_eq!(
        read(msime_client_punctuation_with_context(handle, b',', 0xd800))["ok"],
        false
    );
    read(msime_client_destroy(handle));
}

#[test]
fn paired_book_title_auto_close_balance_is_narrow_and_owned() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    assert_eq!(read(msime_client_focus(handle, true))["ok"], true);
    assert_eq!(
        read(msime_client_punctuation(handle, b'<'))["value"]["commit"],
        "《"
    );
    let before = read(msime_client_view(handle));
    for invalid in [b'(', b'>', b'a', b' ', 0, 128, 255] {
        assert_eq!(
            read(msime_client_balance_paired_punctuation_after_auto_close(
                handle, invalid
            ))["ok"],
            false
        );
        assert_eq!(read(msime_client_view(handle)), before);
    }
    let balanced = read(msime_client_balance_paired_punctuation_after_auto_close(
        handle, b'<',
    ));
    assert_eq!(balanced["ok"], true);
    assert_eq!(balanced["value"], before["value"]);
    assert_eq!(
        read(msime_client_punctuation(handle, b'<'))["value"]["commit"],
        "《"
    );
    read(msime_client_balance_paired_punctuation_after_auto_close(
        handle, b'<',
    ));
    read(msime_client_destroy(handle));
    assert_eq!(
        read(msime_client_balance_paired_punctuation_after_auto_close(
            handle, b'<',
        ))["ok"],
        false
    );
}

#[test]
fn candidate_edge_uses_engine_han_text_and_preserves_unsupported_composition() {
    for (code, first, last) in [("4e2d", "中", "中"), ("20000", "𠀀", "𠀀"), ("41", "", "")] {
        for (edge, expected) in [(0, first), (1, last)] {
            let dir = tempfile::tempdir().unwrap();
            let handle = test_host(dir.path());
            read(msime_client_focus(handle, true));
            read(msime_client_character(handle, b'U', true));
            for byte in code.bytes() {
                read(msime_client_character(handle, byte, false));
            }
            let before = read(msime_client_view(handle))["value"].clone();
            assert!(
                before["candidates"]
                    .as_array()
                    .is_some_and(|items| !items.is_empty()),
                "Missing Unicode fixture candidate for {code}: {before}"
            );
            let id = &before["candidates"][0]["id"];
            let generation = id["generation"].as_u64().unwrap();
            let index = id["index"].as_u64().unwrap() as usize;
            for invalid in [2, 255] {
                assert_eq!(
                    read(msime_client_select_edge(handle, generation, index, invalid))["ok"],
                    false
                );
                assert_eq!(read(msime_client_view(handle))["value"], before);
            }
            assert_eq!(
                read(msime_client_select_edge(
                    handle,
                    generation - 1,
                    index,
                    edge
                ))["ok"],
                false
            );
            assert_eq!(
                read(msime_client_select_edge(
                    handle,
                    generation,
                    usize::MAX,
                    edge
                ))["ok"],
                false
            );
            assert_eq!(
                std::thread::spawn(move || read(msime_client_select_edge(
                    handle, generation, index, edge
                ))["ok"]
                    .clone())
                .join()
                .unwrap(),
                false
            );
            assert_eq!(read(msime_client_view(handle))["value"], before);
            let result = read(msime_client_select_edge(handle, generation, index, edge));
            assert_eq!(result["ok"], true);
            assert_eq!(result["value"]["handled"], !expected.is_empty());
            if expected.is_empty() {
                assert!(result["value"]["commit"].is_null());
                assert_eq!(
                    result["value"]["view"]["editing_text"],
                    before["editing_text"]
                );
                assert_eq!(
                    result["value"]["view"]["candidates"][0]["text"],
                    before["candidates"][0]["text"]
                );
            } else {
                assert_eq!(result["value"]["commit"], expected);
                assert_eq!(result["value"]["view"]["editing_text"], "");
                assert!(result["value"]["view"]["candidates"]
                    .as_array()
                    .unwrap()
                    .is_empty());
            }
            assert_eq!(
                read(msime_client_select_edge(handle, generation, index, edge))["ok"],
                false
            );
            read(msime_client_destroy(handle));
            assert_eq!(
                read(msime_client_select_edge(handle, generation, index, edge))["ok"],
                false
            );
        }
    }
}

#[test]
fn live_punctuation_preserves_composition_and_survives_preferences() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    for byte in b"4e2d" {
        read(msime_client_character(handle, *byte, false));
    }
    let before = read(msime_client_view(handle))["value"].clone();
    for _ in 0..2 {
        let toggled = read(msime_client_set_chinese_punctuation(handle, false));
        assert_eq!(toggled["value"], before);
    }
    let preferences = Preferences {
        candidate_page_size: 2,
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
    let committed = read(msime_client_command(handle, 9));
    assert_eq!(committed["value"]["commit"], "中");
    assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], false);
    let ascii = read(msime_client_character(handle, b',', false));
    assert_eq!(ascii["value"]["handled"], false);
    assert!(ascii["value"]["commit"].is_null());
    assert_eq!(
        read(msime_client_set_chinese_punctuation(handle, true))["ok"],
        true
    );
    assert_eq!(
        read(msime_client_character(handle, b',', false))["value"]["commit"],
        "，"
    );
    assert_eq!(
        std::thread::spawn(
            move || read(msime_client_set_chinese_punctuation(handle, false))["ok"].clone()
        )
        .join()
        .unwrap(),
        false
    );
    read(msime_client_destroy(handle));
    assert_eq!(
        read(msime_client_set_chinese_punctuation(handle, true))["ok"],
        false
    );
}

#[test]
fn dedicated_english_mode_switches_through_host_api() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    let enabled = read(msime_client_set_english_mode(handle, true));
    assert_eq!(enabled["ok"], true);
    assert_eq!(enabled["value"]["focused"], true);
    assert_eq!(enabled["value"]["dedicated_english"], true);
    let typed = read(msime_client_character(handle, b'a', false));
    assert_eq!(typed["value"]["view"]["dedicated_english"], true);
    assert_eq!(typed["value"]["view"]["local_mode"], "none");
    let disabled = read(msime_client_set_english_mode(handle, false));
    assert_eq!(disabled["ok"], true);
    assert_eq!(disabled["value"]["dedicated_english"], false);
    read(msime_client_destroy(handle));
}

#[test]
fn enabling_dedicated_english_cancels_active_composition() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'n', false));
    let composing = read(msime_client_character(handle, b'i', false));
    assert!(!composing["value"]["view"]["editing_text"]
        .as_str()
        .unwrap()
        .is_empty());
    let enabled = read(msime_client_set_english_mode(handle, true));
    assert_eq!(enabled["value"]["dedicated_english"], true);
    assert_eq!(enabled["value"]["editing_text"], "");
    assert!(enabled["value"]["candidates"]
        .as_array()
        .unwrap()
        .is_empty());
    read(msime_client_destroy(handle));
}

// 默认输入状态 = 英文 is the host's passthrough state: the host keeps the
// letters and no session sees them. It must not put the session itself
// into dedicated English. A session that starts there answers the first
// key with English word candidates, and the host's own CN/EN toggle does
// not clear it - so the toggle flips between passthrough English and
// English candidates, and Chinese is unreachable.
#[test]
fn english_default_ime_mode_leaves_dedicated_english_off() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host_preferences(
        dir.path(),
        Preferences {
            default_ime_mode: msime_client_core::preferences::DefaultImeMode::English,
            ..Preferences::default()
        },
    );
    read(msime_client_focus(handle, true));
    assert_eq!(
        read(msime_client_view(handle))["value"]["dedicated_english"],
        false
    );
    let typed = read(msime_client_character(handle, b'n', false));
    assert_eq!(typed["value"]["view"]["dedicated_english"], false);
    // Still reachable - it just has to be asked for, by the menu row or
    // the hotkey that owns it.
    let enabled = read(msime_client_set_english_mode(handle, true));
    assert_eq!(enabled["value"]["dedicated_english"], true);
    read(msime_client_destroy(handle));
}

#[test]
fn preferences_wait_for_commit_keep_handle_and_reject_old_revisions() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    for byte in b"4e2d" {
        read(msime_client_character(handle, *byte, false));
    }
    let before = read(msime_client_view(handle))["value"].clone();
    let prefs = Preferences {
        chinese_punctuation: false,
        candidate_page_size: 2,
        ..Preferences::default()
    };
    let queued = update(handle, 1, &prefs);
    assert_eq!(queued["value"]["deferred"], true);
    assert_eq!(queued["value"]["view"], before);
    let committed = read(msime_client_command(handle, 1));
    assert_eq!(committed["value"]["commit"], "中");
    assert_eq!(committed["value"]["view"]["session"], handle);
    assert_eq!(committed["value"]["view"]["focused"], true);
    assert_eq!(update(handle, 1, &prefs)["value"]["deferred"], false);
    assert_eq!(
        read(msime_client_character(handle, b',', false))["value"]["handled"],
        false
    );
    assert_eq!(update(handle, 0, &prefs)["ok"], false);
    assert_eq!(update(handle, 1, &Preferences::default())["ok"], false);
    let generation = before["generation"].as_u64().unwrap();
    assert_eq!(
        read(msime_client_select(handle, generation, 0))["ok"],
        false
    );
    read(msime_client_destroy(handle));
}
#[test]
fn newest_pending_preferences_win_on_blur_and_invalid_values_are_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    let off = Preferences {
        chinese_punctuation: false,
        ..Preferences::default()
    };
    assert_eq!(update(handle, 1, &off)["value"]["deferred"], true);
    let invalid = Preferences {
        candidate_page_size: 0,
        ..off.clone()
    };
    assert_eq!(update(handle, 20, &invalid)["ok"], false);
    assert_eq!(update(handle, 2, &Preferences::default())["ok"], true);
    read(msime_client_focus(handle, false));
    read(msime_client_focus(handle, true));
    assert_eq!(
        read(msime_client_character(handle, b',', false))["value"]["commit"],
        "，"
    );
    let wrong = std::thread::spawn(move || update(handle, 3, &Preferences::default()))
        .join()
        .unwrap();
    assert_eq!(wrong["ok"], false);
    assert_eq!(
        read(unsafe { msime_client_update_preferences(handle, std::ptr::null(), 0) })["ok"],
        false
    );
    read(msime_client_destroy(handle));
}
#[test]
fn failed_rebuild_preserves_completed_input_and_retries_later() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'U', true));
    for byte in b"4e2d" {
        read(msime_client_character(handle, *byte, false));
    }
    let prefs = Preferences {
        chinese_punctuation: false,
        ..Preferences::default()
    };
    update(handle, 1, &prefs);
    // Inject invalid replacement options without touching the live Engine or disk.
    let original = SESSIONS.with(|sessions| {
        let mut sessions = sessions.borrow_mut();
        let host = sessions.get_mut(&handle).unwrap();
        std::mem::replace(&mut host.options.resources, "relative".into())
    });
    let committed = read(msime_client_command(handle, 1));
    assert_eq!(committed["value"]["commit"], "中");
    assert!(committed["value"]["diagnostic"]
        .as_str()
        .unwrap()
        .contains("Preferences update deferred"));
    SESSIONS.with(|sessions| {
        sessions
            .borrow_mut()
            .get_mut(&handle)
            .unwrap()
            .options
            .resources = original
    });
    assert_eq!(update(handle, 1, &prefs)["value"]["deferred"], false);
    assert_eq!(
        read(msime_client_character(handle, b',', false))["value"]["handled"],
        false
    );
    read(msime_client_destroy(handle));
}
pub(super) fn read(pointer: *mut c_char) -> Value {
    // SAFETY: all callers pass a fresh response allocation.
    let string = unsafe { CString::from_raw(pointer) };
    serde_json::from_slice(string.as_bytes()).unwrap()
}
#[test]
fn native_boundary_drives_real_engine_and_rejects_wrong_thread() {
    let dir = tempfile::tempdir().unwrap();
    let path = |name| {
        let path = dir.path().join(name);
        std::fs::create_dir_all(&path).unwrap();
        path
    };
    let options = json!({ "api_version": 1, "resources": path("resources"), "user_data": path("user"), "cache": path("cache"), "dictionaries": path("dictionaries"), "preferences": { "scheme": "quanpin", "default_ime_mode": "chinese", "candidate_page_size": 5, "learning": false, "chinese_punctuation": true } }).to_string();
    let created = read(unsafe { msime_client_create(options.as_ptr(), options.len()) });
    assert_eq!(created["ok"], true, "{created}");
    let handle = created["value"]["session"].as_u64().unwrap();
    let wrong_thread = std::thread::spawn(move || read(msime_client_view(handle)))
        .join()
        .unwrap();
    assert_eq!(wrong_thread["ok"], false);
    assert_eq!(read(msime_client_focus(handle, true))["ok"], true);
    read(msime_client_character(handle, b'U', true));
    for byte in b"4e2d" {
        assert_eq!(
            read(msime_client_character(handle, *byte, false))["ok"],
            true
        );
    }
    let result = read(msime_client_command(handle, 1));
    assert_eq!(result["value"]["commit"], "中");
    let punctuation = read(msime_client_character(handle, b',', false));
    assert_eq!(punctuation["ok"], true);
    assert_eq!(punctuation["value"]["handled"], true);
    assert_eq!(punctuation["value"]["commit"], "，");
    assert_eq!(read(msime_client_destroy(handle))["ok"], true);
    assert_eq!(read(msime_client_view(handle))["ok"], false);
    assert_eq!(read(msime_client_destroy(handle))["ok"], false);
}
#[test]
fn cloud_response_boundary_guards_identity_permission_and_buffers() {
    let dir = tempfile::tempdir().unwrap();
    let preferences = Preferences {
        scheme: InputScheme::Quanpin,
        cloud_candidates: true,
        ..chinese_preferences()
    };
    let handle = test_host_with_pinyin_fixture(dir.path(), preferences.clone());
    read(msime_client_focus(handle, true));
    assert!(read(msime_client_online_query(handle))["value"].is_null());
    for byte in b"nihao" {
        read(msime_client_character(handle, *byte, false));
    }
    let query = read(msime_client_online_query(handle))["value"].to_string();
    let body = r#"["SUCCESS", [["nihao", ["你好"]]]]"#.as_bytes();
    let apply = |target, query: &str, body: &[u8]| {
        read(unsafe {
            msime_client_apply_cloud_response(
                target,
                query.as_ptr(),
                query.len(),
                body.as_ptr(),
                body.len(),
            )
        })
    };
    let before = read(msime_client_view(handle))["value"].clone();
    assert!(!before["candidates"].as_array().unwrap().is_empty());
    for candidate in ["", "bad\nvalue"] {
        let result = read(unsafe {
            msime_client_apply_online_candidate(
                handle,
                query.as_ptr(),
                query.len(),
                candidate.as_ptr(),
                candidate.len(),
                0,
            )
        });
        assert_eq!(result["value"]["applied"], false);
        assert_eq!(result["value"]["view"], before);
    }
    let malformed = apply(handle, &query, b"not json");
    assert_eq!(malformed["value"]["applied"], false);
    assert_eq!(malformed["value"]["view"], before);
    assert_eq!(apply(handle, &query, body)["value"]["applied"], true);
    let after_cloud = read(msime_client_view(handle))["value"].clone();
    assert_ne!(after_cloud["generation"], before["generation"]);
    assert_eq!(after_cloud["editing_text"], before["editing_text"]);
    let other_dir = tempfile::tempdir().unwrap();
    let other = test_host_preferences(other_dir.path(), preferences.clone());
    read(msime_client_focus(other, true));
    for byte in b"nihao" {
        read(msime_client_character(other, *byte, false));
    }
    assert_eq!(apply(other, &query, body)["value"]["applied"], false);
    read(msime_client_character(handle, b'a', false));
    assert_eq!(apply(handle, &query, body)["value"]["applied"], false);
    let current = read(msime_client_online_query(handle))["value"].to_string();
    let disabled = Preferences {
        cloud_candidates: false,
        ..preferences
    };
    assert_eq!(update(handle, 1, &disabled)["value"]["deferred"], true);
    assert_eq!(
        read(msime_client_online_query(handle))["value"]["cloud_candidates"],
        false
    );
    assert_eq!(apply(handle, &current, body)["value"]["applied"], false);
    for (q, qlen, b, blen) in [
        (std::ptr::null(), 0, body.as_ptr(), body.len()),
        (query.as_ptr(), query.len(), std::ptr::null(), 0),
        (query.as_ptr(), 16385, body.as_ptr(), body.len()),
        (query.as_ptr(), query.len(), body.as_ptr(), 262145),
    ] {
        assert_eq!(
            read(unsafe { msime_client_apply_cloud_response(handle, q, qlen, b, blen) })["ok"],
            false
        );
    }
    assert_eq!(
        apply(handle, "invalid", body)["error"],
        "invalid online query document"
    );
    read(msime_client_destroy(other));
    read(msime_client_destroy(handle));
}

#[test]
fn cloud_candidate_requires_an_existing_local_candidate_page() {
    let dir = tempfile::tempdir().unwrap();
    let preferences = Preferences {
        scheme: InputScheme::Quanpin,
        cloud_candidates: true,
        ..chinese_preferences()
    };
    let handle = test_host_preferences(dir.path(), preferences);
    read(msime_client_focus(handle, true));
    for byte in b"nihao" {
        read(msime_client_character(handle, *byte, false));
    }
    let query = read(msime_client_online_query(handle))["value"].to_string();
    let before = read(msime_client_view(handle))["value"].clone();
    assert!(before["candidates"].as_array().unwrap().is_empty());
    let candidate = "你好";
    let result = read(unsafe {
        msime_client_apply_online_candidate(
            handle,
            query.as_ptr(),
            query.len(),
            candidate.as_ptr(),
            candidate.len(),
            0,
        )
    });
    assert_eq!(result["value"]["applied"], false);
    assert_eq!(result["value"]["view"], before);
    read(msime_client_destroy(handle));
}

#[test]
fn ai_queries_and_delivery_follow_pending_preferences() {
    let dir = tempfile::tempdir().unwrap();
    let mut preferences = Preferences {
        scheme: InputScheme::Quanpin,
        ..chinese_preferences()
    };
    preferences.ai_assistant.enabled = true;
    preferences.ai_assistant.model = "synthetic-original".into();
    preferences.ai_assistant.token = "synthetic-private".into();
    // An enabled assistant with no endpoint has nowhere to send anything;
    // a real one is always configured with the provider's URL.
    preferences.ai_assistant.endpoint = "https://api.deepseek.com/chat/completions".into();
    let handle = test_host_preferences(dir.path(), preferences.clone());
    read(msime_client_focus(handle, true));
    for byte in b"nihaoshijie" {
        read(msime_client_character(handle, *byte, false));
    }
    let apply = |query: &Value, batch: bool| {
        let query = query.to_string();
        if batch {
            let candidates = serde_json::to_vec(&json!(["合成候选"])).unwrap();
            read(unsafe {
                msime_client_apply_online_candidates(
                    handle,
                    query.as_ptr(),
                    query.len(),
                    candidates.as_ptr(),
                    candidates.len(),
                    1,
                )
            })
        } else {
            let candidate = "合成候选".as_bytes();
            read(unsafe {
                msime_client_apply_online_candidate(
                    handle,
                    query.as_ptr(),
                    query.len(),
                    candidate.as_ptr(),
                    candidate.len(),
                    1,
                )
            })
        }
    };
    let original = read(msime_client_online_query(handle))["value"].clone();
    assert_eq!(original["ai_eligible"], true);
    assert!(!original.to_string().contains("synthetic-private"));
    let original_bytes = original.to_string();
    let descriptor = read(unsafe {
        msime_client_ai_request_for_query(handle, original_bytes.as_ptr(), original_bytes.len())
    });
    assert_eq!(descriptor["ok"], true);
    assert_eq!(descriptor["value"]["method"], "POST");
    assert_eq!(
        descriptor["value"]["headers"]["Content-Type"],
        "application/json"
    );
    for revision in 1..=5 {
        let old = read(msime_client_online_query(handle))["value"].clone();
        match revision {
            1 => preferences.ai_assistant.enabled = false,
            2 => {
                preferences.ai_assistant.enabled = true;
                preferences.ai_assistant.model = "synthetic-new".into();
            }
            3 => {
                preferences.ai_assistant.endpoint =
                    "https://synthetic.invalid/v1/chat/completions".into()
            }
            4 => preferences.ai_assistant.prompt = "synthetic prompt".into(),
            _ => preferences.ai_assistant.candidate_limit = 1,
        }
        assert_eq!(
            update(handle, revision, &preferences)["value"]["deferred"],
            true
        );
        let current = read(msime_client_online_query(handle))["value"].clone();
        assert_eq!(current["generation"], original["generation"]);
        assert_eq!(current["query_text"], original["query_text"]);
        assert_eq!(
            current["ai_assistant"].is_null(),
            !preferences.ai_assistant.enabled
        );
        if preferences.ai_assistant.enabled {
            assert_eq!(
                current["ai_assistant"]["model"],
                preferences.ai_assistant.model
            );
            assert_eq!(
                current["ai_assistant"]["endpoint"],
                preferences.ai_assistant.endpoint
            );
            assert_eq!(
                current["ai_assistant"]["prompt"],
                preferences.ai_assistant.prompt
            );
            assert_eq!(
                current["ai_assistant"]["candidate_limit"],
                preferences.ai_assistant.candidate_limit
            );
        }
        for batch in [false, true] {
            assert_eq!(apply(&old, batch)["value"]["applied"], false);
        }
    }
    let current = read(msime_client_online_query(handle))["value"].clone();
    let before_ai = read(msime_client_view(handle))["value"].clone();
    assert_eq!(apply(&current, true)["value"]["applied"], true);
    let after_ai = read(msime_client_view(handle))["value"].clone();
    assert_ne!(after_ai["generation"], before_ai["generation"]);
    read(msime_client_destroy(handle));
}
#[test]
fn custom_translation_plan_preserves_direction_and_filters_visible_sources() {
    let plan = |request: Value| {
        let bytes = serde_json::to_vec(&request).unwrap();
        read(unsafe { msime_client_custom_translation_plan(bytes.as_ptr(), bytes.len()) })
    };
    let candidates = json!([
        {"text":"Hello","source":4},
        {"text":"测试","source":0},
        {"text":"Hello","source":4},
        {"text":"smile","source":6},
        {"text":"smile","source":7},
        {"text":"123","source":0},
        {"text":"test😀","source":0},
        {"text":"x".repeat(41),"source":0},
        {"text":"unknown","source":10}
    ]);
    for target in ["en", "fr", "ja", "es", "ru", "de", "ko"] {
        assert_eq!(
            plan(json!({"target_language":target,"candidates":candidates}))["value"],
            json!([
                {"text":"Hello","key":"hello","source_language":"en","target_language":"zh"},
                {"text":"测试","key":"测试","source_language":"zh","target_language":target}
            ])
        );
    }
    for request in [
        json!({"target_language":"unknown","candidates":[]}),
        json!({"target_language":"en","candidates":vec![json!({"text":"hello","source":0}); 10]}),
        json!({"target_language":"en","candidates":[{"text":"hello","source":true}]}),
    ] {
        assert_eq!(plan(request)["ok"], false);
    }
    assert_eq!(
        read(unsafe { msime_client_custom_translation_plan(std::ptr::null(), 0) })["ok"],
        false
    );
}
#[test]
fn learned_translation_buffers_are_bounded() {
    assert_eq!(
        read(unsafe { msime_client_ai_http_request(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_ai_http_request(b"x".as_ptr(), 65537) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_parse_ai_response(b"x".as_ptr(), 1048577, 1) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_parse_ai_response(b"x".as_ptr(), 1, 11) })["ok"],
        false
    );
    for (pointer, length) in [(std::ptr::null(), 0), (b"x".as_ptr(), 65537)] {
        assert_eq!(
            read(unsafe { msime_client_learned_translation_request(pointer, length) })["ok"],
            false
        );
    }
}
#[test]
fn tencent_translation_buffers_are_bounded() {
    assert_eq!(
        read(unsafe { msime_client_tencent_translation_http_request(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_tencent_translation_http_request(b"x".as_ptr(), 65537) })["ok"],
        false
    );
    for (length, expected) in [(1048577, 1), (1, 0), (1, 10)] {
        assert_eq!(
            read(unsafe {
                msime_client_parse_tencent_translation_response(b"x".as_ptr(), length, expected)
            })["ok"],
            false
        );
    }
}
#[test]
fn custom_translation_http_bridge_is_bounded_and_pure() {
    let build = |request: Value| {
        let bytes = serde_json::to_vec(&request).unwrap();
        read(unsafe { msime_client_custom_translation_http_request(bytes.as_ptr(), bytes.len()) })
    };
    let request = json!({"config":{"enabled":true,"endpoint":"https://translation.invalid/api","api_key":"synthetic"},
        "text":"hello","source_language":"en","target_language":"zh"});
    let value = build(request.clone());
    assert_eq!(value["ok"], true);
    assert_eq!(value["value"]["method"], "POST");
    assert_eq!(
        value["value"]["headers"]["Authorization"],
        "Bearer synthetic"
    );
    assert_eq!(
        value["value"]["body"],
        json!({"text":"hello","source_lang":"EN","target_lang":"ZH"})
    );
    assert_eq!(value["value"]["timeout_ms"], 2500);
    assert_eq!(value["value"]["max_response_bytes"], 1048576);
    let mut padded = request.clone();
    padded["config"]["endpoint"] = json!("  https://translation.invalid/api  ");
    padded["config"]["api_key"] = json!("  synthetic  ");
    let padded_value = build(padded);
    assert_eq!(
        padded_value["value"]["url"],
        "https://translation.invalid/api"
    );
    assert_eq!(
        padded_value["value"]["headers"]["Authorization"],
        "Bearer synthetic"
    );
    let mut disabled = request.clone();
    disabled["config"]["enabled"] = json!(false);
    assert!(build(disabled)["value"].is_null());
    let mut keyless = request.clone();
    keyless["config"]["api_key"] = json!("");
    assert!(build(keyless)["value"]["headers"]
        .get("Authorization")
        .is_none());
    for (field, value) in [
        ("text", "x".repeat(41)),
        ("source_language", "en\r\n".into()),
    ] {
        let mut invalid = request.clone();
        invalid[field] = json!(value);
        assert_eq!(
            build(invalid)["error"],
            "invalid custom translation parameters"
        );
    }
    for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
        let control = char::from_u32(codepoint).unwrap();
        let mut invalid = request.clone();
        invalid["text"] = json!(format!("before{control}after"));
        assert_eq!(
            build(invalid)["error"],
            "invalid custom translation parameters"
        );
    }
    for (field, value) in [
        ("endpoint", "file:///synthetic"),
        ("api_key", "synthetic\r\nheader"),
    ] {
        let mut invalid = request.clone();
        invalid["config"][field] = json!(value);
        assert_eq!(
            build(invalid)["error"],
            "invalid custom translation parameters"
        );
    }
    let parse = |body: &[u8]| {
        read(unsafe { msime_client_parse_custom_translation_response(body.as_ptr(), body.len()) })
    };
    assert_eq!(parse(br#"{"data":"translated"}"#)["value"], "translated");
    assert_eq!(
        parse(br#"{"data":"  hello\nworld\t "}"#)["value"],
        "hello world"
    );
    assert!(parse(br#"{"data":"bad\u0000gloss"}"#)["value"].is_null());
    for body in [
        b"invalid".as_slice(),
        br#"{"code":500,"data":"ignored"}"#,
        b"\xff",
    ] {
        assert!(parse(body)["value"].is_null());
    }
    assert!(parse(json!({"data":"x".repeat(4097)}).to_string().as_bytes())["value"].is_null());
    assert_eq!(
        read(unsafe { msime_client_custom_translation_http_request(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_parse_custom_translation_response(b"x".as_ptr(), 1048577) })
            ["ok"],
        false
    );
}
#[test]
fn invalid_buffers_and_commands_return_owned_errors() {
    assert_eq!(
        read(unsafe { msime_client_prepare_host(std::ptr::null(), 0) })["ok"],
        false
    );
    let invalid = br#"{"resources":"relative","state_root":"relative"}"#;
    assert_eq!(
        read(unsafe { msime_client_prepare_host(invalid.as_ptr(), invalid.len()) })["ok"],
        false
    );
    assert_eq!(
        read(unsafe { msime_client_create(std::ptr::null(), 0) })["ok"],
        false
    );
    assert_eq!(read(msime_client_command(0, 999))["ok"], false);
    unsafe { msime_client_string_free(std::ptr::null_mut()) };
}

#[test]
fn candidate_page_edge_commands_reach_runtime() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    for byte in b"nihao" {
        read(msime_client_character(handle, *byte, false));
    }
    let first = read(msime_client_command(handle, 104));
    assert_eq!(first["value"]["handled"], false);
    assert!(first["value"]["view"]["candidates"]
        .as_array()
        .unwrap()
        .is_empty());
    let last = read(msime_client_command(handle, 105));
    assert_eq!(last["value"]["handled"], false);
    assert_eq!(read(msime_client_destroy(handle))["ok"], true);
}

#[test]
fn complete_candidate_abi_keeps_view_paged_and_selects_a_later_entry() {
    let dir = tempfile::tempdir().unwrap();
    let handle = test_host(dir.path());
    read(msime_client_focus(handle, true));
    read(msime_client_character(handle, b'T', true));
    read(msime_client_character(handle, b'r', false));
    let transition = read(msime_client_character(handle, b'q', false));
    let view = &transition["value"]["view"];
    let generation = view["generation"].as_u64().unwrap();
    let visible_count = view["candidates"].as_array().unwrap().len();
    assert!(visible_count > 0);

    let complete = read(msime_client_all_candidates(handle));
    assert_eq!(complete["ok"], true);
    assert_eq!(complete["value"]["session"], handle);
    assert_eq!(complete["value"]["generation"], generation);
    assert_eq!(complete["value"]["preedit"], "Trq");
    let complete_count = complete["value"]["candidates"].as_array().unwrap().len();
    assert!(complete_count > visible_count);
    let later = complete["value"]["candidates"][visible_count]["id"]["index"]
        .as_u64()
        .unwrap() as usize;

    assert_eq!(
        read(msime_client_select(handle, generation, later))["ok"],
        false
    );
    assert_eq!(
        read(msime_client_select_any_candidate(
            handle,
            generation + 1,
            later
        ))["ok"],
        false
    );
    assert_eq!(
        read(msime_client_select_any_candidate(
            handle,
            generation,
            complete_count
        ))["ok"],
        false
    );
    let selected = read(msime_client_select_any_candidate(handle, generation, later));
    assert_eq!(selected["ok"], true);
    assert_eq!(selected["value"]["handled"], true);
    assert!(selected["value"]["commit"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    assert_eq!(read(msime_client_destroy(handle))["ok"], true);
}

#[test]
#[cfg(unix)]
fn emoji_catalog_pagination_preserves_legacy_defaults() {
    let legacy: crate::ffi::EmojiCatalogQuery = serde_json::from_str("{}").unwrap();
    assert!(!legacy.cursor);
    assert_eq!(legacy.offset, 0);
    assert_eq!(legacy.panel.limit, 48);
    let page: crate::ffi::EmojiCatalogQuery = serde_json::from_str(
        r#"{"search":"synthetic","category":"symbols","offset":510,"limit":255}"#,
    )
    .unwrap();
    assert_eq!(page.offset, 510);
    assert_eq!(page.panel.search, "synthetic");
    assert_eq!(page.panel.category, "symbols");
    assert_eq!(page.panel.limit, 255);
    assert!(serde_json::from_str::<crate::ffi::EmojiCatalogQuery>(r#"{"offset":-1}"#).is_err());
}

#[test]
#[cfg(unix)]
fn emoji_catalog_cursor_advances_over_invalid_rows_and_preserves_duplicates() {
    let directory = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(directory.path().join("others.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE emoji(emoji TEXT,category TEXT,keywords TEXT,pinyin TEXT,sort_order INTEGER);
         CREATE TABLE kaomoji_catalog(kaomoji TEXT,keywords TEXT,sort_order INTEGER);
         CREATE TABLE symbol_catalog(symbol TEXT,category TEXT,parent_category TEXT,keywords TEXT,sort_order INTEGER);",
    ).unwrap();
    for (index, text) in [
        None,
        Some(""),
        Some("synthetic-same"),
        Some("synthetic-same"),
        Some("synthetic-tail"),
    ]
    .into_iter()
    .enumerate()
    {
        db.execute(
            "INSERT INTO emoji VALUES (?1,'fixture','match','',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
        db.execute(
            "INSERT INTO kaomoji_catalog VALUES (?1,'match',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
        db.execute(
            "INSERT INTO symbol_catalog VALUES (?1,'fixture','fixture','match',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
    }
    let resources = directory.path().to_str().unwrap().as_bytes();
    let request = |category: &str, offset: usize, limit: u8, cursor: bool| {
        let query = serde_json::to_vec(&json!({
            "category": category, "offset": offset, "limit": limit, "cursor": cursor,
        }))
        .unwrap();
        read(unsafe {
            msime_client_emoji_catalog_request(
                query.as_ptr(),
                query.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    for category in ["", "kaomoji", "symbols"] {
        let empty = request(category, 0, 2, true);
        assert_eq!(empty["ok"], true);
        assert_eq!(
            empty["value"],
            json!({"items":[], "next_offset":2, "complete":false})
        );
        let duplicates = request(category, 2, 2, true);
        assert_eq!(duplicates["value"]["items"].as_array().unwrap().len(), 2);
        assert_eq!(duplicates["value"]["next_offset"], 4);
        assert_eq!(duplicates["value"]["complete"], false);
        let tail = request(category, 4, 2, true);
        assert_eq!(tail["value"]["items"][0]["text"], "synthetic-tail");
        assert_eq!(tail["value"]["next_offset"], 5);
        assert_eq!(tail["value"]["complete"], true);
        let exact = request(category, 4, 1, true);
        assert_eq!(exact["value"]["complete"], false);
        assert_eq!(
            request(category, 5, 1, true)["value"],
            json!({"items":[], "next_offset":5, "complete":true})
        );
        let legacy = request(category, 2, 2, false);
        assert_eq!(legacy["value"]["items"].as_array().unwrap().len(), 1);
        assert!(legacy["value"].get("complete").is_none());
        assert_eq!(request(category, 0, 0, true)["ok"], false);
    }
}

#[test]
#[cfg(unix)]
fn emoji_catalog_cursor_skips_invalid_groups_without_stalling() {
    let directory = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(directory.path().join("others.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE emoji(emoji TEXT,category TEXT,keywords TEXT,pinyin TEXT,sort_order INTEGER);
         INSERT INTO emoji VALUES ('synthetic-invalid',NULL,'','',0);
         INSERT INTO emoji VALUES ('synthetic-invalid','','','',1);
         INSERT INTO emoji VALUES ('synthetic-valid','fixture','','',2);",
    )
    .unwrap();
    let resources = directory.path().to_str().unwrap().as_bytes();
    let request = |offset: usize| {
        let query = serde_json::to_vec(&json!({"cursor":true,"offset":offset,"limit":2})).unwrap();
        read(unsafe {
            msime_client_emoji_catalog_request(
                query.as_ptr(),
                query.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    assert_eq!(
        request(0)["value"],
        json!({"items":[],"next_offset":2,"complete":false})
    );
    let tail = request(2);
    assert_eq!(tail["value"]["items"][0]["text"], "synthetic-valid");
    assert_eq!(tail["value"]["complete"], true);
}

#[test]
#[cfg(unix)]
fn emoji_catalog_ffi_reads_beyond_first_page() {
    let directory = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(directory.path().join("others.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE emoji(emoji TEXT,category TEXT,keywords TEXT,pinyin TEXT,sort_order INTEGER);
         CREATE TABLE kaomoji_catalog(kaomoji TEXT,keywords TEXT,sort_order INTEGER);
         CREATE TABLE symbol_catalog(symbol TEXT,category TEXT,parent_category TEXT,keywords TEXT,sort_order INTEGER);",
    ).unwrap();
    for index in 0..520 {
        let text = format!("synthetic-{index}");
        db.execute(
            "INSERT INTO emoji VALUES (?1,'fixture','match','',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
        db.execute(
            "INSERT INTO kaomoji_catalog VALUES (?1,'match',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
        db.execute(
            "INSERT INTO symbol_catalog VALUES (?1,'fixture','fixture','match',?2)",
            rusqlite::params![text, index],
        )
        .unwrap();
    }
    let resources = directory.path().to_str().unwrap().as_bytes();
    let request = |category: &str, offset: usize, limit: u8| {
        let query = serde_json::to_vec(
            &json!({"category":category,"search":"match","offset":offset,"limit":limit}),
        )
        .unwrap();
        read(unsafe {
            msime_client_emoji_catalog_request(
                query.as_ptr(),
                query.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    for category in ["", "kaomoji", "symbols"] {
        for (offset, count) in [(0, 255), (255, 255), (510, 10), (765, 0)] {
            let page = request(category, offset, 255);
            assert_eq!(page["ok"], true);
            assert_eq!(page["value"]["items"].as_array().unwrap().len(), count);
            if count > 0 {
                assert_eq!(
                    page["value"]["items"][0]["text"],
                    format!("synthetic-{offset}")
                );
            }
        }
    }
    db.execute(
        "UPDATE emoji SET emoji='synthetic-0' WHERE sort_order=1",
        [],
    )
    .unwrap();
    assert_eq!(
        request("", 0, 2)["value"]["items"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(
        request("", 2, 2)["value"]["items"][0]["text"],
        "synthetic-2"
    );
    assert_eq!(request("", 0, 0)["ok"], false);
    assert_eq!(request("", usize::MAX, 255)["ok"], false);
}

#[test]
#[cfg(unix)]
fn emoji_catalog_errors_are_not_empty_results() {
    let directory = tempfile::tempdir().unwrap();
    let resources = directory.path().to_str().unwrap().as_bytes();
    let request = |category: &str| {
        let query = serde_json::to_vec(&json!({"category":category})).unwrap();
        read(unsafe {
            msime_client_emoji_catalog_request(
                query.as_ptr(),
                query.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    let unavailable = json!({"ok":false,"error":"local emoji catalog unavailable"});
    assert_eq!(request(""), unavailable);
    let path = directory.path().join("others.db");
    assert!(!path.exists(), "read-only query must not create resources");
    std::fs::write(&path, b"synthetic invalid sqlite file").unwrap();
    for category in ["", "kaomoji", "symbols"] {
        assert_eq!(request(category), unavailable);
    }
    std::fs::remove_file(&path).unwrap();
    let db = rusqlite::Connection::open(&path).unwrap();
    assert_eq!(request(""), unavailable);
    db.execute_batch("CREATE TABLE emoji(emoji TEXT,category TEXT,keywords TEXT,pinyin TEXT,sort_order INTEGER);
        CREATE TABLE kaomoji_catalog(kaomoji TEXT,keywords TEXT,sort_order INTEGER);
        CREATE TABLE symbol_catalog(symbol TEXT,category TEXT,parent_category TEXT,keywords TEXT,sort_order INTEGER);").unwrap();
    for category in ["", "kaomoji", "symbols"] {
        assert_eq!(request(category), json!({"ok":true,"value":{"items":[]}}));
    }
    // A query can prepare successfully but fail while stepping it.
    db.execute_batch(
        "DROP TABLE emoji;
        CREATE VIEW emoji AS SELECT abs(-9223372036854775808) AS emoji,
            '' AS category, '' AS keywords, '' AS pinyin, 0 AS sort_order;",
    )
    .unwrap();
    assert_eq!(request(""), unavailable);
}

#[test]
#[cfg(unix)]
fn emoji_groups_preserve_catalog_order_and_filter_before_paging() {
    let directory = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(directory.path().join("others.db")).unwrap();
    db.execute_batch("CREATE TABLE emoji(emoji TEXT,category TEXT,keywords TEXT,pinyin TEXT,sort_order INTEGER);
        INSERT INTO emoji VALUES ('one','Z','match','',1),('two','A','match','',2),('three','Z','match','',3),('four','Z','other','',4);
        CREATE TABLE symbol_catalog(symbol TEXT,category TEXT,parent_category TEXT,keywords TEXT,sort_order INTEGER);
        INSERT INTO symbol_catalog VALUES ('one','Z','parent','match',1),('two','A','parent','match',2),('three','Z','parent','match',3),('four','Z','parent','other',4);
        CREATE TABLE kaomoji_catalog(kaomoji TEXT,keywords TEXT,sort_order INTEGER);
        INSERT INTO kaomoji_catalog VALUES ('fixture','match',1);").unwrap();
    let resources = directory.path().to_str().unwrap().as_bytes();
    let request = |query: Value| {
        let query = serde_json::to_vec(&query).unwrap();
        read(unsafe {
            msime_client_emoji_catalog_request(
                query.as_ptr(),
                query.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    for category in ["", "symbols"] {
        assert_eq!(
            request(json!({"category":category,"list_groups":true}))["value"]["groups"],
            json!(["Z", "A"])
        );
        let page =
            request(json!({"category":category,"group":"Z","search":"match","offset":1,"limit":1}));
        assert_eq!(page["ok"], true);
        assert_eq!(page["value"]["items"].as_array().unwrap().len(), 1);
        assert_eq!(page["value"]["items"][0]["text"], "three");
        assert_eq!(
            request(json!({"category":category,"group":"' OR 1=1 --"}))["value"]["items"],
            json!([])
        );
    }
    assert_eq!(
        request(json!({"category":"kaomoji","list_groups":true}))["value"]["groups"],
        json!(["All"])
    );
    assert_eq!(
        request(json!({"category":"kaomoji","group":"missing"}))["value"]["items"],
        json!([])
    );
    db.execute_batch("UPDATE symbol_catalog SET category='Shared', parent_category=CASE WHEN sort_order=2 THEN 'Parent-B' ELSE 'Parent-A' END WHERE sort_order<4;
        UPDATE symbol_catalog SET parent_category='' WHERE sort_order=4;").unwrap();
    assert_eq!(
        request(json!({"list_symbol_groups":true}))["value"]["symbol_groups"],
        json!([
            {"parent":"Parent-A","title":"Shared"}, {"parent":"Parent-B","title":"Shared"}, {"parent":"Z","title":"Z"}
        ])
    );
    let page = request(
        json!({"category":"symbols","parent":"Parent-A","group":"Shared","search":"match","offset":1,"limit":1}),
    );
    assert_eq!(page["value"]["items"][0]["text"], "three");
    let other = request(json!({"category":"symbols","parent":"Parent-B","group":"Shared"}));
    assert_eq!(other["value"]["items"].as_array().unwrap().len(), 1);
    assert_eq!(other["value"]["items"][0]["text"], "two");
    assert_eq!(
        request(json!({"category":"symbols","parent":"missing"}))["value"]["items"],
        json!([])
    );
    assert_eq!(request(json!({"parent":"Parent-A"}))["ok"], false);
    db.execute_batch("DROP TABLE emoji").unwrap();
    assert_eq!(request(json!({"list_groups":true}))["ok"], false);
}

#[test]
fn translation_persistence_rejects_control_keys_before_writing() {
    let user = tempfile::tempdir().unwrap();
    let user_path = user.path().to_str().unwrap();
    let save = |translations: Value| {
        let request = serde_json::to_vec(&json!({
            "target_language": "en",
            "translations": translations,
        }))
        .unwrap();
        read(unsafe {
            msime_client_translation_gloss_save(
                request.as_ptr(),
                request.len(),
                user_path.as_ptr(),
                user_path.len(),
            )
        })
    };

    for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
        let control = char::from_u32(codepoint).unwrap();
        let result = save(json!([
            {"text":"你好","translation":"hello"},
            {"text":format!("测试{control}"),"translation":"test"},
        ]));
        assert_eq!(result["ok"], false);
        assert_eq!(
            result["error"],
            "translation persistence entries exceed limits"
        );
        assert!(!user.path().join("translation-glosses.db").exists());
    }

    let saved = save(json!([
        {"text":"你好","translation":"  hello\tworld\r\n"},
    ]));
    assert_eq!(saved["value"]["saved"], 1);
    let database = rusqlite::Connection::open(user.path().join("translation-glosses.db")).unwrap();
    assert_eq!(
        database
            .query_row(
                "SELECT english_gloss FROM zh_en_glosses WHERE chinese='你好'",
                [],
                |row| row.get::<_, String>(0),
            )
            .unwrap(),
        "hello world"
    );
}

#[test]
fn candidate_gloss_requests_reject_control_keys() {
    let resources = tempfile::tempdir().unwrap();
    let resources_path = resources.path().to_str().unwrap().as_bytes();
    let call = |text: String| {
        let request = serde_json::to_vec(&json!({
            "generation": 1,
            "candidates": [{"text": text, "source": 0}],
        }))
        .unwrap();
        read(unsafe {
            msime_client_candidate_gloss_request(
                request.as_ptr(),
                request.len(),
                resources_path.as_ptr(),
                resources_path.len(),
            )
        })
    };

    for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
        let control = char::from_u32(codepoint).unwrap();
        let result = call(format!("测试{control}"));
        assert_eq!(result["ok"], false);
        assert_eq!(result["error"], "candidate gloss entries exceed limits");
    }
}

#[test]
fn candidate_gloss_request_uses_packaged_dictionary_and_bounds_input() {
    let directory = tempfile::tempdir().unwrap();
    let db = rusqlite::Connection::open(directory.path().join("english.db")).unwrap();
    db.execute_batch(
        "CREATE TABLE english_words(word TEXT COLLATE BINARY NOT NULL,display TEXT NOT NULL,weight INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(word,display)) WITHOUT ROWID;
         CREATE TABLE en_zh_glosses(english TEXT COLLATE BINARY PRIMARY KEY,chinese_gloss TEXT NOT NULL) WITHOUT ROWID;
         CREATE TABLE zh_en_glosses(chinese TEXT COLLATE BINARY PRIMARY KEY,english_gloss TEXT NOT NULL) WITHOUT ROWID;
         INSERT INTO english_words VALUES ('hello','hello',1);
         INSERT INTO en_zh_glosses VALUES ('hello',' 你好； 您好 ；喂');
         INSERT INTO zh_en_glosses VALUES ('你好',' hello ; greeting ; salutation');
         INSERT INTO zh_en_glosses VALUES ('你好！','hello there');",
    )
    .unwrap();
    let resources = directory.path().to_str().unwrap().as_bytes();
    let call = |request: Value, resources: &[u8]| {
        let request = serde_json::to_vec(&request).unwrap();
        read(unsafe {
            msime_client_candidate_gloss_request(
                request.as_ptr(),
                request.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };
    let result = call(
        json!({
            "generation": 42,
            "candidates": [
                {"text":"你好","source":0},
                {"text":"Hello","source":4},
                {"text":"🙂","source":6},
                {"text":"mixed混合","source":0},
                {"text":"你好！","source":0}
            ]
        }),
        resources,
    );
    assert_eq!(result["ok"], true);
    assert_eq!(result["value"]["generation"], 42);
    assert_eq!(
        result["value"]["translations"],
        json!([
            {"text":"你好","translation":"hello; greeting"},
            {"text":"Hello","translation":"你好; 您好"},
            {"text":"你好！","translation":"hello there"}
        ])
    );
    let user = tempfile::tempdir().unwrap();
    let user_path = user.path().to_str().unwrap();
    let save = |target: &str, translations: Value| {
        let request =
            serde_json::to_vec(&json!({"target_language":target,"translations":translations}))
                .unwrap();
        read(unsafe {
            msime_client_translation_gloss_save(
                request.as_ptr(),
                request.len(),
                user_path.as_ptr(),
                user_path.len(),
            )
        })
    };
    let entries = json!([
        {"text":"你好","translation":" learned   greeting "},
        {"text":"SYNTHETIC","translation":"合成释义"},
        {"text":"unchanged","translation":"UNCHANGED"},
        {"text":"long","translation":"x".repeat(33)},
        {"text":"🙂","translation":"emoji"}
    ]);
    assert_eq!(save("fr", entries.clone())["value"]["saved"], 0);
    assert!(!user.path().join("translation-glosses.db").exists());
    assert_eq!(save("en", entries)["value"]["saved"], 2);
    // Each API call opens a fresh Engine dictionary, proving durable reuse.
    let learned = call(
        json!({"generation":43,"user_data":user_path,"candidates":[
            {"text":"你好","source":0},{"text":"Synthetic","source":4},{"text":"Hello","source":4}
        ]}),
        resources,
    );
    assert_eq!(
        learned["value"]["translations"],
        json!([
            {"text":"你好","translation":"learned greeting"},
            {"text":"Synthetic","translation":"合成释义"},
            {"text":"Hello","translation":"你好; 您好"}
        ])
    );
    assert_eq!(
        db.query_row(
            "SELECT english_gloss FROM zh_en_glosses WHERE chinese='你好'",
            [],
            |row| row.get::<_, String>(0)
        )
        .unwrap(),
        " hello ; greeting ; salutation"
    );
    assert_eq!(
        call(
            json!({"generation":1,"user_data":"relative","candidates":[]}),
            resources
        )["ok"],
        false
    );
    assert_eq!(
        call(json!({"generation":1,"candidates":[]}), b"relative")["ok"],
        false
    );
    assert_eq!(
        call(
            json!({"generation":1,"candidates":[{"text":"","source":0}]}),
            resources
        )["ok"],
        false
    );
    db.execute(
        "UPDATE zh_en_glosses SET english_gloss=?1 WHERE chinese='你好'",
        ["x".repeat(4097)],
    )
    .unwrap();
    assert_eq!(
        call(
            json!({"generation":1,"candidates":[{"text":"你好","source":0}]}),
            resources
        )["ok"],
        false
    );
    let missing = tempfile::tempdir().unwrap();
    assert_eq!(
        call(
            json!({"generation":1,"candidates":[{"text":"你好","source":0}]}),
            missing.path().to_str().unwrap().as_bytes()
        ),
        json!({"ok":false,"error":"candidate gloss dictionary unavailable"})
    );
    assert!(!missing.path().join("english.db").exists());
}

#[test]
fn english_completion_request_queries_dictionary_and_rejects_invalid_input() {
    let directory = tempfile::tempdir().unwrap();
    let database = rusqlite::Connection::open(directory.path().join("english.db")).unwrap();
    database
        .execute_batch(
            "CREATE TABLE english_words(word TEXT COLLATE BINARY NOT NULL,display TEXT NOT NULL,weight INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(word,display)) WITHOUT ROWID;
             INSERT INTO english_words VALUES ('hello','Hello',10),('help','help',5),('hero','hero',1);",
        )
        .unwrap();
    let resources = directory.path().to_str().unwrap().as_bytes();
    let call = |request: Value, resources: &[u8]| {
        let request = serde_json::to_vec(&request).unwrap();
        read(unsafe {
            msime_client_english_completions_request(
                request.as_ptr(),
                request.len(),
                resources.as_ptr(),
                resources.len(),
            )
        })
    };

    assert_eq!(
        call(json!({"prefix":"he","limit":3}), resources),
        json!({"ok":true,"value":{"prefix":"he","items":["Hello","help","hero"]}})
    );
    assert_eq!(
        call(json!({"prefix":"he","limit":1}), resources)["value"]["items"],
        json!(["Hello"])
    );

    for request in [
        json!({"prefix":"","limit":1}),
        json!({"prefix":"he1","limit":1}),
        json!({"prefix":format!("he{}", '\u{1}'),"limit":1}),
        json!({"prefix":"he","limit":0}),
        json!({"prefix":"he","limit":33}),
    ] {
        assert_eq!(call(request, resources)["ok"], false);
    }
    assert_eq!(
        call(json!({"prefix":"he","limit":1}), b"relative")["error"],
        "resources path must be absolute"
    );
    assert!(!directory.path().join("english.db-journal").exists());
}

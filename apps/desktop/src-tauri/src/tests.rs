//! Unit tests for the parent module, in their own file because the module
//! is large enough that mixing them with the implementation obscured both.
//! Same `mod tests` as before, so `use super::*` still names the parent.

#[cfg(any(target_os = "macos", target_os = "windows"))]
mod credential_command_tests;

#[cfg(not(target_os = "android"))]
#[test]
fn ai_endpoint_validation_accepts_http_api_urls_and_rejects_unsafe_urls() {
    for endpoint in [
        "https://api.example.test/v1/chat/completions",
        "http://127.0.0.1:8080/v1/chat/completions?tenant=fixture",
    ] {
        assert!(super::validate_ai_endpoint(endpoint).is_ok());
    }
    for endpoint in [
        "file:///tmp/models",
        "https://user:password@example.test/v1/chat/completions",
        "https://example.test/v1/chat/completions#fragment",
        "https://example.test/v1/chat/\ncompletions",
    ] {
        assert!(super::validate_ai_endpoint(endpoint).is_err());
    }
}

#[cfg(not(target_os = "android"))]
#[test]
fn ai_models_url_reuses_the_api_prefix() {
    let endpoint = super::validate_ai_endpoint(
        "https://api.example.test/openai/v1/chat/completions?tenant=fixture",
    )
    .unwrap_or_else(|_| panic!("fixture endpoint should be valid"));
    assert_eq!(
        super::ai_models_url(&endpoint).as_str(),
        "https://api.example.test/openai/v1/models"
    );

    let endpoint = super::validate_ai_endpoint("https://api.example.test/chat/completions")
        .unwrap_or_else(|_| panic!("fixture endpoint should be valid"));
    assert_eq!(
        super::ai_models_url(&endpoint).as_str(),
        "https://api.example.test/v1/models"
    );
}

#[cfg(not(target_os = "android"))]
#[test]
fn ai_credentials_and_text_reject_empty_or_unsafe_values() {
    assert!(super::validate_ai_token("fixture-token").is_ok());
    assert!(super::validate_ai_token("").is_err());
    assert!(super::validate_ai_token("fixture\n-token").is_err());
    assert!(super::ai_text_is_valid("多行\nfixture text\t", false));
    assert!(super::ai_text_is_valid("", true));
    assert!(!super::ai_text_is_valid("", false));
    assert!(!super::ai_text_is_valid("fixture\0text", false));
}

#[test]
fn clipboard_text_validation_enforces_nonempty_nul_free_byte_limit() {
    assert!(!super::clipboard_text_is_valid(""));
    assert!(!super::clipboard_text_is_valid("a\0b"));

    let at_limit = "x".repeat(msime_client_core::clipboard::MAX_TEXT_BYTES);
    assert!(super::clipboard_text_is_valid(&at_limit));

    let over_limit = format!("{at_limit}x");
    assert!(!super::clipboard_text_is_valid(&over_limit));
    assert!(super::clipboard_text_is_valid(
        "第一行\nsecond line\n第三行"
    ));
}

#[test]
fn windows_restart_payload_is_exact_utf16_without_terminator() {
    let payload = super::windows_restart_payload();
    let expected: Vec<u8> = "RestartServer"
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect();
    assert_eq!(payload, expected);
    assert_eq!(payload.len(), "RestartServer".encode_utf16().count() * 2);
}

#[test]
fn external_links_require_clean_https_urls() {
    for url in [
        "https://example.com/help",
        "https://updates.example.com/v1?channel=stable",
    ] {
        assert!(super::external_url_is_safe(url));
    }
    for url in [
        "https://",
        "https:///path",
        "http://example.com",
        "https://example.com/help path",
        "https://example.com/a&b",
        "https://example.com/\"quoted\"",
        "https://example.com/\\escape",
    ] {
        assert!(!super::external_url_is_safe(url));
    }
    assert!(!super::external_url_is_safe(&format!(
        "https://example.com/{}",
        "x".repeat(4096)
    )));
}

#[test]
fn ios_clipboard_history_is_permission_gated_not_preference_gated() {
    assert!(!super::clipboard_history_uses_preference(
        msime_client_core::host_surface::HostPlatform::Ios
    ));
    for platform in [
        msime_client_core::host_surface::HostPlatform::Windows,
        msime_client_core::host_surface::HostPlatform::Macos,
        msime_client_core::host_surface::HostPlatform::Linux,
        msime_client_core::host_surface::HostPlatform::Android,
    ] {
        assert!(super::clipboard_history_uses_preference(platform));
    }
}

#[test]
fn ios_routes_only_app_group_dictionary_operations() {
    for operation in [
        "list",
        "edit",
        "import_personal",
        "export",
        "retry",
        "dismiss_failure",
    ] {
        assert!(super::ios_personal_dictionary_action(
            &serde_json::json!({ "operation": operation })
        ));
    }
    for action in [
        serde_json::json!({ "operation": "import" }),
        serde_json::json!({ "operation": "unknown" }),
        serde_json::json!({}),
        serde_json::Value::Null,
    ] {
        assert!(!super::ios_personal_dictionary_action(&action));
    }
}

#[test]
fn ios_first_run_host_options_use_packaged_resources_and_shared_state() {
    let document = super::ios_host_options_document(
        None,
        std::path::Path::new("/fixture/resources"),
        std::path::Path::new("/fixture/shared-state"),
    )
    .expect("first-run options");
    assert_eq!(document["resources"], "/fixture/resources");
    assert_eq!(document["state_root"], "/fixture/shared-state");
}

#[test]
fn ios_named_skin_library_shares_the_apple_app_group_root() {
    let root =
        super::ios_custom_skin_library_root(std::path::Path::new("/fixture/app-group/MSIME"));
    assert_eq!(root, std::path::Path::new("/fixture/app-group"));
    assert_eq!(
        msime_client_core::skin::custom_library::CustomSkinLibraryStore::new(root).path(),
        std::path::Path::new("/fixture/app-group/CustomSkins/library.json")
    );
}

#[test]
fn ios_community_reply_library_shares_the_keyboard_app_group_file() {
    assert_eq!(
        super::ios_community_resource_library_path(std::path::Path::new(
            "/fixture/app-group/MSIME"
        )),
        std::path::Path::new("/fixture/app-group/CommunityLibrary.json")
    );
}

#[test]
fn ios_prepared_host_options_are_preserved_and_malformed_json_is_rejected() {
    let prepared = r#"{"resources":"/prepared","state_root":"/state","api_version":1}"#;
    let document = super::ios_host_options_document(
        Some(prepared),
        std::path::Path::new("/unused/resources"),
        std::path::Path::new("/unused/state"),
    )
    .expect("prepared options");
    assert_eq!(document["resources"], "/prepared");
    assert_eq!(document["state_root"], "/state");
    assert!(super::ios_host_options_document(
        Some("{"),
        std::path::Path::new("/unused/resources"),
        std::path::Path::new("/unused/state"),
    )
    .is_err());
}

#[test]
fn ios_voice_batch_configuration_uses_current_preferences_and_safe_defaults() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.voice_input.asr_provider = "openai".into();
    preferences.voice_input.asr_endpoint.clear();
    preferences.voice_input.asr_model.clear();
    preferences.voice_input.asr_token = "synthetic-current".into();
    preferences
        .voice_input
        .asr_tokens
        .insert("openai".into(), "synthetic-stale".into());
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.provider, "openai");
    assert_eq!(
        configuration.endpoint,
        "https://api.openai.com/v1/audio/transcriptions"
    );
    assert_eq!(configuration.model, "whisper-1");
    assert_eq!(configuration.token, "synthetic-current");
    assert!(configuration.headers.is_empty());

    preferences.voice_input.asr_provider = "groq".into();
    preferences.voice_input.asr_endpoint = "https://fixture.invalid/transcribe".into();
    preferences.voice_input.asr_model = "fixture-model".into();
    preferences.voice_input.asr_token.clear();
    preferences
        .voice_input
        .asr_tokens
        .insert("groq".into(), "synthetic-slot".into());
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.endpoint, "https://fixture.invalid/transcribe");
    assert_eq!(configuration.model, "fixture-model");
    assert_eq!(configuration.token, "synthetic-slot");
    assert!(configuration.headers.is_empty());
}

#[test]
fn ios_keyboard_ai_preferences_resolve_origin_tokens_and_disable_incomplete_drafts() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.ai_assistant.enabled = true;
    preferences.ai_assistant.provider = "deepseek".into();
    preferences.ai_assistant.endpoint =
        "https://API.Example.invalid/v1/chat/completions".into();
    preferences.ai_assistant.model = "fixture-model".into();
    preferences.ai_assistant.prompt = "只返回结果".into();
    preferences.ai_assistant.tokens.insert(
        "https://api.example.invalid:443".into(),
        "fixture-origin-token".into(),
    );
    let native = super::ios_keyboard_ai_preferences(&preferences.ai_assistant);
    assert!(native.enabled);
    assert_eq!(native.provider, "deepSeek");
    assert_eq!(native.token, "fixture-origin-token");

    preferences.ai_assistant.tokens.clear();
    assert!(!super::ios_keyboard_ai_preferences(&preferences.ai_assistant).enabled);
}

#[test]
fn ios_voice_doubao_configuration_uses_shared_auth_and_current_preferences() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.voice_input.asr_token = "synthetic-key".into();
    preferences.voice_input.asr_app_key = "stale-app".into();
    preferences.voice_input.doubao_auth_mode = "api_key".into();
    preferences.voice_input.doubao_boosting_table_id = "fixture-table".into();
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.provider, "doubao");
    assert_eq!(
        configuration.endpoint,
        "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    );
    assert!(configuration.model.is_empty());
    assert!(configuration.token.is_empty());
    assert!(configuration.enable_itn);
    assert!(configuration.enable_punctuation);
    assert!(!configuration.enable_ddc);
    assert_eq!(configuration.boosting_table_id, "fixture-table");
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-key" && header.value == "synthetic-key"));
    assert!(!configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-app-key"));

    preferences.voice_input.doubao_auth_mode = "legacy".into();
    preferences.voice_input.asr_app_key = "synthetic-app".into();
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-app-key" && header.value == "synthetic-app"));
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-access-key"));
}

#[cfg(unix)]
#[test]
fn voice_provider_options_only_forwards_known_doubao_auth_modes() {
    let document = serde_json::json!({
        "preferences": {"voice_input": {
            "doubao_auth_mode": "legacy",
            "asr_app_key": "private-app-id",
            "asr_token": "private-token"
        }}
    });
    let result = super::voice_provider_options(&document);
    assert!(result.is_ok());
    let options = result.ok().expect("voice options should be valid");
    assert_eq!(
        options.get("doubao_auth_mode").and_then(|v| v.as_str()),
        Some("legacy")
    );
    assert!(options.get("asr_app_key").is_none());
    assert!(options.get("asr_token").is_none());

    let document = serde_json::json!({
        "preferences": {"voice_input": {"doubao_auth_mode": "unknown"}}
    });
    let result = super::voice_provider_options(&document);
    assert!(result.is_ok());
    let options = result.ok().expect("voice options should be valid");
    assert!(options.get("doubao_auth_mode").is_none());
}

#[cfg(unix)]
#[test]
fn voice_provider_options_bound_strings_by_utf8_bytes() {
    let multibyte = "界".repeat(200);
    let document = serde_json::json!({
        "preferences": {"voice_input": {
            "asr_model": multibyte,
            "capture_device": "x".repeat(600)
        }}
    });
    let options = super::voice_provider_options(&document).unwrap();
    let model = options
        .get("asr_model")
        .and_then(|value| value.as_str())
        .unwrap();
    let device = options
        .get("capture_device")
        .and_then(|value| value.as_str())
        .unwrap();

    assert_eq!(model.len(), 510);
    assert_eq!(model.chars().count(), 170);
    assert_eq!(device.len(), 512);
}

#[cfg(unix)]
#[test]
fn voice_preferences_refresh_keeps_transport_and_reads_latest_store_snapshot() {
    let root = tempfile::tempdir().unwrap();
    let store = super::PreferencesStore::new(root.path());
    let initial = store.load().unwrap();
    let mut preferences = initial.preferences;
    preferences.voice_input.asr_provider = "openai".into();
    let saved = store.save(initial.revision, preferences).unwrap();
    let document = serde_json::json!({
        "voice_provider_socket": "/fixture/voice.sock",
        "preferences": {"voice_input": {"asr_provider": "stale"}}
    });
    let refreshed = super::refresh_voice_preferences(document, &store).unwrap();
    assert_eq!(
        refreshed["preferences"]["voice_input"]["asr_provider"],
        "openai"
    );
    assert_eq!(refreshed["voice_provider_socket"], "/fixture/voice.sock");
    assert_eq!(saved.revision, store.load().unwrap().revision);
}

#[cfg(unix)]
#[test]
fn credential_tests_route_to_the_configured_provider_without_credentials() {
    let document = serde_json::json!({
        "online_provider_socket": "/fixture/online.sock",
        "translation_provider_socket": "/fixture/translation.sock",
        "voice_provider_socket": "/fixture/voice.sock",
    });
    assert_eq!(
        super::credential_provider_socket(&document, "ai.assistant"),
        Some(std::path::PathBuf::from("/fixture/online.sock"))
    );
    assert_eq!(
        super::credential_provider_socket(&document, "translation.niutrans"),
        Some(std::path::PathBuf::from("/fixture/translation.sock"))
    );
    assert_eq!(
        super::credential_provider_socket(&document, "voice.polish"),
        Some(std::path::PathBuf::from("/fixture/voice.sock"))
    );
    assert!(super::credential_provider_socket(&document, "unknown").is_none());
}

#[test]
fn second_launch_routes_are_taken_from_explicit_arguments() {
    use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};

    assert_eq!(
        super::launch_route_from_args(&["--route=emoji".into()]),
        Some(SurfaceRoute::Emoji)
    );
    assert_eq!(
        super::launch_route_from_args(&["--route=settings:about".into()])
            .and_then(|route| route.settings_category()),
        Some(SettingsCategory::About)
    );
    assert_eq!(
        super::launch_route_from_args(&["--route=../private".into()]),
        None
    );
    assert_eq!(super::launch_route_from_args(&["--other".into()]), None);
}

#[test]
fn dictionary_mutations_quiesce_but_reads_do_not() {
    assert!(super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "edit"})
    ));
    assert!(super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "import"})
    ));
    assert!(super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "reset"})
    ));
    assert!(!super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "list"})
    ));
    assert!(!super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "export"})
    ));
}

#[test]
fn macos_restart_targets_the_input_method_bundle() {
    assert_eq!(
        super::macos_input_source_restart_args(),
        [
            "-n",
            "-b",
            "app.msime.client.preview.inputmethod",
            "--args",
            "--reregister-input-source",
        ]
    );
}

#[test]
fn settings_routes_select_a_page_the_shared_ui_accepts() {
    use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};
    // The route wins over the compatibility variable, and every category the
    // contract accepts survives the settings-page identifier filter.
    for category in SettingsCategory::ALL {
        let page =
            super::settings_page_from_route(Some(SurfaceRoute::Settings(Some(category))));
        assert_eq!(
            super::requested_settings_page(page.as_deref()),
            Some(category.as_str().to_owned()),
            "category {category:?} is not a usable settings page id"
        );
    }
    assert_eq!(
        super::settings_page_from_route(Some(SurfaceRoute::Settings(None))),
        None
    );
    assert_eq!(
        super::settings_page_from_route(Some(SurfaceRoute::Emoji)),
        None
    );
}

#[test]
fn requested_settings_page_only_accepts_a_plain_section_identifier() {
    assert_eq!(
        super::requested_settings_page(Some(" about ")),
        Some("about".into())
    );
    assert_eq!(
        super::requested_settings_page(Some("screen-keyboard")),
        Some("screen-keyboard".into())
    );
    assert_eq!(super::requested_settings_page(None), None);
    assert_eq!(super::requested_settings_page(Some("   ")), None);
    // Anything that could carry a path, a query or a script stays out of
    // the window the launcher is about to open.
    assert_eq!(super::requested_settings_page(Some("../etc")), None);
    assert_eq!(super::requested_settings_page(Some("About")), None);
    assert_eq!(super::requested_settings_page(Some("a?b=c")), None);
    assert_eq!(super::requested_settings_page(Some(&"a".repeat(33))), None);
}

#[test]
fn packaged_handwriting_model_only_accepts_an_existing_absolute_file() {
    let directory = tempfile::tempdir().unwrap();
    let model = directory.path().join("handwriting-zh_CN.model");
    std::fs::write(&model, b"synthetic").unwrap();
    let options = |value: String| serde_json::json!({ "handwriting_model": value }).to_string();

    // The host options win when they name a model that is actually there.
    assert_eq!(
        super::packaged_handwriting_model(&options(model.to_string_lossy().into_owned())),
        Some(model.clone())
    );

    // A relative or missing path is refused rather than handed to the
    // recognizer, so a stale setting cannot send strokes at something else.
    assert_eq!(
        super::packaged_handwriting_model(&options("model".into())),
        None
    );
    assert_eq!(
        super::packaged_handwriting_model(&options(
            directory
                .path()
                .join("absent.model")
                .to_string_lossy()
                .into_owned()
        )),
        None
    );
}

#[test]
fn typing_statistics_status_reports_file_availability_without_content() {
    let directory = tempfile::tempdir().unwrap();
    let store =
        msime_client_core::typing_statistics::TypingStatisticsStore::new(directory.path());
    let missing = super::typing_statistics_status(&store, store.load().unwrap())
        .ok()
        .unwrap();
    let missing_json = serde_json::to_value(missing).unwrap();
    assert_eq!(missing_json["availability"], "neverWritten");
    assert!(missing_json["lastWrittenMs"].is_null());
    assert_eq!(missing_json["statistics"]["enabled"], true);

    let disabled = store.set_enabled(false).unwrap();
    let ready = super::typing_statistics_status(&store, disabled)
        .ok()
        .unwrap();
    let ready_json = serde_json::to_value(ready).unwrap();
    assert_eq!(ready_json["availability"], "ready");
    assert!(ready_json["lastWrittenMs"].is_number());
    assert_eq!(ready_json["statistics"]["enabled"], false);
}

#[cfg(target_os = "linux")]
#[test]
fn panel_input_targets_are_isolated_by_surface() {
    let state = super::PanelInputState::default();
    let mut targets = state.0.lock().unwrap();
    targets.insert(
        "emoji-panel".into(),
        super::PanelInputTarget::X11("11".into()),
    );
    targets.insert(
        "keyboard-panel".into(),
        super::PanelInputTarget::X11("22".into()),
    );
    targets.remove("emoji-panel");
    assert!(targets.get("emoji-panel").is_none());
    assert!(matches!(
        targets.get("keyboard-panel"),
        Some(super::PanelInputTarget::X11(window)) if window == "22"
    ));
}

#[cfg(not(target_os = "windows"))]
#[test]
fn keyboard_does_not_accept_focus_but_editable_panels_do() {
    assert!(!super::panel_accepts_focus("keyboard-panel"));
    for label in [
        "handwriting-panel",
        "voice-panel",
        "emoji-panel",
        "cloud-clipboard-panel",
        "cloud-dictionary-panel",
    ] {
        assert!(super::panel_accepts_focus(label));
    }
}
#[test]
fn toolbar_stylesheet_command_errors_do_not_expose_paths() {
    let state = tempfile::tempdir().unwrap();
    let result =
        super::read_skin_toolbar_stylesheet_at(state.path().join("skins"), "../sample");
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("expected error"),
    };
    assert_eq!(
        serde_json::to_value(error).unwrap(),
        serde_json::json!({ "code": "storage" })
    );
}
#[test]
fn skin_image_command_contract_filters_non_images_and_paths() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let folder = root.join("sample");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(folder.join("skin.toml"), "schema_version = 1\nid = 'sample'\nname = 'Sample'\nversion = '1'\nbase = 'fluent'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n[candidate_window]\n[candidate_window.decoration]\n").unwrap();
    std::fs::write(folder.join("preview.png"), [0, 1, 255]).unwrap();
    std::fs::write(folder.join("font.woff2"), [0, 1, 255]).unwrap();
    std::fs::write(folder.join("toolbar.css"), b".sample {}").unwrap();
    assert!(matches!(
        super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"),
        Ok(None)
    ));
    let manifest = std::fs::read_to_string(folder.join("skin.toml")).unwrap();
    std::fs::write(
        folder.join("skin.toml"),
        format!("toolbar_stylesheet = 'toolbar.css'\n{manifest}"),
    )
    .unwrap();
    assert!(
        matches!(super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"), Ok(Some(css)) if css == ".sample {}")
    );
    let result = super::read_skin_image_at(root.clone(), "sample", "preview.png")
        .ok()
        .unwrap();
    let json = serde_json::to_value(result).unwrap();
    assert_eq!(json["contentType"], "image/png");
    assert_eq!(json["bytes"], serde_json::json!([0, 1, 255]));
    let font = super::read_skin_font_at(root.clone(), "sample", "font.woff2")
        .ok()
        .unwrap();
    let font_json = serde_json::to_value(font).unwrap();
    assert_eq!(font_json["contentType"], "font/woff2");
    assert_eq!(font_json["bytes"], serde_json::json!([0, 1, 255]));
    assert!(super::read_skin_font_at(root.clone(), "sample", "preview.png").is_err());
    assert!(super::read_skin_font_at(root.clone(), "sample", "../font.woff2").is_err());
    assert!(super::read_skin_font_at(root.clone(), "../sample", "font.woff2").is_err());
    assert!(super::read_skin_image_at(root.clone(), "sample", "toolbar.css").is_err());
    assert!(super::read_skin_image_at(root.clone(), "sample", "../preview.png").is_err());
    assert!(super::read_skin_image_at(root, "../sample", "preview.png").is_err());
}

#[test]
fn skin_catalog_response_uses_host_root_and_preserves_scan_results() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let folder = root.join("sample");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(
        folder.join("skin.toml"),
        r#"schema_version = 1
id = 'sample'
name = 'Sample'
version = '1'
base = 'fluent'
[supports]
layouts = ['vertical']
themes = ['light']
[candidate_window]
[candidate_window.decoration]
"#,
    )
    .unwrap();
    std::fs::create_dir(root.join("Bad")).unwrap();
    let result = serde_json::to_value(super::read_skin_catalog(root.clone())).unwrap();
    assert_eq!(result["directory"], root.to_string_lossy().as_ref());
    assert_eq!(result["packages"][0]["id"], "sample");
    assert_eq!(result["packages"].as_array().unwrap().len(), 1);
    assert_eq!(result["issues"].as_array().unwrap().len(), 1);
    assert_eq!(
        result["packages"][0]["layouts"],
        serde_json::json!(["vertical"])
    );
    assert_eq!(result["issues"][0]["folder"], "Bad");
    assert!(result.get("catalog").is_none());
}

#[test]
fn scanning_missing_skin_directory_does_not_create_it() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let result = super::read_skin_catalog(root.clone());
    assert!(result.catalog.packages.is_empty());
    assert!(result.catalog.issues.is_empty());
    assert!(!root.exists());
}

#[cfg(target_os = "linux")]
use super::*;

#[cfg(target_os = "linux")]
#[test]
fn linux_xdotool_geometry_requires_complete_numeric_shell_fields() {
    let geometry = "WINDOW=4194305\nX=120\nY=48\nWIDTH=1280\nHEIGHT=720\nSCREEN=1\n";
    assert_eq!(
        parse_xdotool_geometry(geometry),
        Some((120.0, 48.0, 1280.0, 720.0))
    );

    for malformed in [
        "X=120\nY=48\nWIDTH=1280\n",
        "X=120\nY=48\nWIDTH=1280\nHEIGHT=oops\n",
        "X=120\nY=48\nWIDTH=1280\nHEIGHT=720\nBROKEN",
    ] {
        assert_eq!(parse_xdotool_geometry(malformed), None);
    }
}

#[cfg(target_os = "linux")]
#[test]
fn linux_x11_panel_target_pid_matching_rejects_our_own_window() {
    assert!(x11_window_is_owned_by_process("4242\n", 4242));
    assert!(!x11_window_is_owned_by_process("4243\n", 4242));
    assert!(!x11_window_is_owned_by_process("not-a-pid\n", 4242));
    assert!(!x11_window_is_owned_by_process("", 4242));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_panel_text_uses_clipboard_for_non_ascii_on_keymap_backends() {
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::X11("11".into()),
        "你好😀"
    ));
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::Ydotool,
        "你好"
    ));
    assert!(!panel_text_requires_clipboard(
        &PanelInputTarget::Wayland,
        "你好😀"
    ));
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::Wayland,
        "line\nnext"
    ));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_sway_target_and_geometry_walk_nested_and_floating_nodes() {
    let tree = serde_json::json!({
        "type": "root",
        "nodes": [{
            "type": "workspace",
            "id": 7,
            "rect": {"x": 10, "y": 20, "width": 1600, "height": 900},
            "nodes": [{
                "type": "con",
                "id": 42,
                "focused": true,
                "rect": {"x": 110, "y": 220, "width": 900, "height": 600}
            }],
            "floating_nodes": [{
                "type": "floating_con",
                "id": 99,
                "rect": {"x": 300, "y": 400, "width": 300, "height": 200}
            }]
        }]
    });

    assert_eq!(focused_sway_container(&tree), Some(42));
    assert_eq!(
        sway_rect_for_container(&tree, 42),
        Some((110.0, 220.0, 900.0, 600.0))
    );
    assert_eq!(
        sway_rect_for_container(&tree, 99),
        Some((300.0, 400.0, 300.0, 200.0))
    );
    assert_eq!(
        sway_workspace_for_container(&tree, 42, None),
        Some((10.0, 20.0, 1600.0, 900.0))
    );
    assert_eq!(sway_rect_for_container(&tree, 404), None);
    assert_eq!(sway_workspace_for_container(&tree, 404, None), None);
}

#[cfg(target_os = "linux")]
#[test]
fn linux_sway_workspace_does_not_leak_across_sibling_workspaces() {
    let tree = serde_json::json!({
        "type": "root",
        "nodes": [
            {"type": "workspace", "id": 1,
             "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
             "nodes": [{"id": 11, "rect": {"x": 0, "y": 0, "width": 800, "height": 600}}]},
            {"type": "workspace", "id": 2,
             "rect": {"x": 800, "y": 0, "width": 800, "height": 600},
             "nodes": [{"id": 22, "rect": {"x": 800, "y": 0, "width": 800, "height": 600}}]}
        ]
    });

    assert_eq!(
        sway_workspace_for_container(&tree, 22, None),
        Some((800.0, 0.0, 800.0, 600.0))
    );
    assert_eq!(sway_workspace_for_container(&tree, 33, None), None);
}

#[cfg(target_os = "linux")]
#[test]
fn runtime_options_sync_replaces_preferences_atomically() {
    let directory = tempfile::tempdir().expect("temporary directory");
    let path = directory.path().join("runtime-options.json");
    let document = serde_json::json!({
        "api_version": 1,
        "resources": "/resources",
        "preferences": {"candidate_page_size": 5}
    });
    std::fs::write(&path, serde_json::to_vec(&document).unwrap()).unwrap();
    let state = RuntimeOptionsState {
        path: Some(path.clone()),
        document: Arc::new(Mutex::new(document)),
    };
    let mut preferences = Preferences::default();
    preferences.candidate_page_size = 9;
    sync_runtime_options(&state, &preferences).unwrap();
    let updated: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(updated["preferences"]["candidate_page_size"], 9);
}
}
||||||| parent of 31b00ee9 (refactor: move oversized inline test modules into their own files)
mod tests {
#[cfg(any(target_os = "macos", target_os = "windows"))]
mod credential_command_tests;

#[cfg(not(target_os = "android"))]
#[test]
fn ai_endpoint_validation_accepts_http_api_urls_and_rejects_unsafe_urls() {
    for endpoint in [
        "https://api.example.test/v1/chat/completions",
        "http://127.0.0.1:8080/v1/chat/completions?tenant=fixture",
    ] {
        assert!(super::validate_ai_endpoint(endpoint).is_ok());
    }
    for endpoint in [
        "file:///tmp/models",
        "https://user:password@example.test/v1/chat/completions",
        "https://example.test/v1/chat/completions#fragment",
        "https://example.test/v1/chat/\ncompletions",
    ] {
        assert!(super::validate_ai_endpoint(endpoint).is_err());
    }
}

#[cfg(not(target_os = "android"))]
#[test]
fn ai_models_url_reuses_the_api_prefix() {
    let endpoint = super::validate_ai_endpoint(
        "https://api.example.test/openai/v1/chat/completions?tenant=fixture",
    )
    .unwrap_or_else(|_| panic!("fixture endpoint should be valid"));
    assert_eq!(
        super::ai_models_url(&endpoint).as_str(),
        "https://api.example.test/openai/v1/models"
    );

    let endpoint = super::validate_ai_endpoint("https://api.example.test/chat/completions")
        .unwrap_or_else(|_| panic!("fixture endpoint should be valid"));
    assert_eq!(
        super::ai_models_url(&endpoint).as_str(),
        "https://api.example.test/v1/models"
    );
}

#[cfg(not(target_os = "android"))]
#[test]
fn ai_credentials_and_text_reject_empty_or_unsafe_values() {
    assert!(super::validate_ai_token("fixture-token").is_ok());
    assert!(super::validate_ai_token("").is_err());
    assert!(super::validate_ai_token("fixture\n-token").is_err());
    assert!(super::ai_text_is_valid("多行\nfixture text\t", false));
    assert!(super::ai_text_is_valid("", true));
    assert!(!super::ai_text_is_valid("", false));
    assert!(!super::ai_text_is_valid("fixture\0text", false));
}

#[test]
fn clipboard_text_validation_enforces_nonempty_nul_free_byte_limit() {
    assert!(!super::clipboard_text_is_valid(""));
    assert!(!super::clipboard_text_is_valid("a\0b"));

    let at_limit = "x".repeat(msime_client_core::clipboard::MAX_TEXT_BYTES);
    assert!(super::clipboard_text_is_valid(&at_limit));

    let over_limit = format!("{at_limit}x");
    assert!(!super::clipboard_text_is_valid(&over_limit));
    assert!(super::clipboard_text_is_valid(
        "第一行\nsecond line\n第三行"
    ));
}

#[test]
fn windows_restart_payload_is_exact_utf16_without_terminator() {
    let payload = super::windows_restart_payload();
    let expected: Vec<u8> = "RestartServer"
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect();
    assert_eq!(payload, expected);
    assert_eq!(payload.len(), "RestartServer".encode_utf16().count() * 2);
}

#[test]
fn external_links_require_clean_https_urls() {
    for url in [
        "https://example.com/help",
        "https://updates.example.com/v1?channel=stable",
    ] {
        assert!(super::external_url_is_safe(url));
    }
    for url in [
        "https://",
        "https:///path",
        "http://example.com",
        "https://example.com/help path",
        "https://example.com/a&b",
        "https://example.com/\"quoted\"",
        "https://example.com/\\escape",
    ] {
        assert!(!super::external_url_is_safe(url));
    }
    assert!(!super::external_url_is_safe(&format!(
        "https://example.com/{}",
        "x".repeat(4096)
    )));
}

#[test]
fn ios_clipboard_history_is_permission_gated_not_preference_gated() {
    assert!(!super::clipboard_history_uses_preference(
        msime_client_core::host_surface::HostPlatform::Ios
    ));
    for platform in [
        msime_client_core::host_surface::HostPlatform::Windows,
        msime_client_core::host_surface::HostPlatform::Macos,
        msime_client_core::host_surface::HostPlatform::Linux,
        msime_client_core::host_surface::HostPlatform::Android,
    ] {
        assert!(super::clipboard_history_uses_preference(platform));
    }
}

#[test]
fn ios_routes_only_app_group_dictionary_operations() {
    for operation in [
        "list",
        "edit",
        "import_personal",
        "export",
        "retry",
        "dismiss_failure",
    ] {
        assert!(super::ios_personal_dictionary_action(
            &serde_json::json!({ "operation": operation })
        ));
    }
    for action in [
        serde_json::json!({ "operation": "import" }),
        serde_json::json!({ "operation": "unknown" }),
        serde_json::json!({}),
        serde_json::Value::Null,
    ] {
        assert!(!super::ios_personal_dictionary_action(&action));
    }
}

#[test]
fn ios_first_run_host_options_use_packaged_resources_and_shared_state() {
    let document = super::ios_host_options_document(
        None,
        std::path::Path::new("/fixture/resources"),
        std::path::Path::new("/fixture/shared-state"),
    )
    .expect("first-run options");
    assert_eq!(document["resources"], "/fixture/resources");
    assert_eq!(document["state_root"], "/fixture/shared-state");
}

#[test]
fn ios_named_skin_library_shares_the_apple_app_group_root() {
    let root =
        super::ios_custom_skin_library_root(std::path::Path::new("/fixture/app-group/MSIME"));
    assert_eq!(root, std::path::Path::new("/fixture/app-group"));
    assert_eq!(
        msime_client_core::skin::custom_library::CustomSkinLibraryStore::new(root).path(),
        std::path::Path::new("/fixture/app-group/CustomSkins/library.json")
    );
}

#[test]
fn ios_community_reply_library_shares_the_keyboard_app_group_file() {
    assert_eq!(
        super::ios_community_resource_library_path(std::path::Path::new(
            "/fixture/app-group/MSIME"
        )),
        std::path::Path::new("/fixture/app-group/CommunityLibrary.json")
    );
}

#[test]
fn ios_prepared_host_options_are_preserved_and_malformed_json_is_rejected() {
    let prepared = r#"{"resources":"/prepared","state_root":"/state","api_version":1}"#;
    let document = super::ios_host_options_document(
        Some(prepared),
        std::path::Path::new("/unused/resources"),
        std::path::Path::new("/unused/state"),
    )
    .expect("prepared options");
    assert_eq!(document["resources"], "/prepared");
    assert_eq!(document["state_root"], "/state");
    assert!(super::ios_host_options_document(
        Some("{"),
        std::path::Path::new("/unused/resources"),
        std::path::Path::new("/unused/state"),
    )
    .is_err());
}

#[test]
fn ios_voice_batch_configuration_uses_current_preferences_and_safe_defaults() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.voice_input.asr_provider = "openai".into();
    preferences.voice_input.asr_endpoint.clear();
    preferences.voice_input.asr_model.clear();
    preferences.voice_input.asr_token = "synthetic-current".into();
    preferences
        .voice_input
        .asr_tokens
        .insert("openai".into(), "synthetic-stale".into());
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.provider, "openai");
    assert_eq!(
        configuration.endpoint,
        "https://api.openai.com/v1/audio/transcriptions"
    );
    assert_eq!(configuration.model, "whisper-1");
    assert_eq!(configuration.token, "synthetic-current");
    assert!(configuration.headers.is_empty());

    preferences.voice_input.asr_provider = "groq".into();
    preferences.voice_input.asr_endpoint = "https://fixture.invalid/transcribe".into();
    preferences.voice_input.asr_model = "fixture-model".into();
    preferences.voice_input.asr_token.clear();
    preferences
        .voice_input
        .asr_tokens
        .insert("groq".into(), "synthetic-slot".into());
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.endpoint, "https://fixture.invalid/transcribe");
    assert_eq!(configuration.model, "fixture-model");
    assert_eq!(configuration.token, "synthetic-slot");
    assert!(configuration.headers.is_empty());
}

#[test]
fn ios_keyboard_ai_preferences_resolve_origin_tokens_and_disable_incomplete_drafts() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.ai_assistant.enabled = true;
    preferences.ai_assistant.provider = "deepseek".into();
    preferences.ai_assistant.endpoint =
        "https://API.Example.invalid/v1/chat/completions".into();
    preferences.ai_assistant.model = "fixture-model".into();
    preferences.ai_assistant.prompt = "只返回结果".into();
    preferences.ai_assistant.tokens.insert(
        "https://api.example.invalid:443".into(),
        "fixture-origin-token".into(),
    );
    let native = super::ios_keyboard_ai_preferences(&preferences.ai_assistant);
    assert!(native.enabled);
    assert_eq!(native.provider, "deepSeek");
    assert_eq!(native.token, "fixture-origin-token");

    preferences.ai_assistant.tokens.clear();
    assert!(!super::ios_keyboard_ai_preferences(&preferences.ai_assistant).enabled);
}

#[test]
fn ios_voice_doubao_configuration_uses_shared_auth_and_current_preferences() {
    let mut preferences = msime_client_core::preferences::Preferences::default();
    preferences.voice_input.asr_token = "synthetic-key".into();
    preferences.voice_input.asr_app_key = "stale-app".into();
    preferences.voice_input.doubao_auth_mode = "api_key".into();
    preferences.voice_input.doubao_boosting_table_id = "fixture-table".into();
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert_eq!(configuration.provider, "doubao");
    assert_eq!(
        configuration.endpoint,
        "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
    );
    assert!(configuration.model.is_empty());
    assert!(configuration.token.is_empty());
    assert!(configuration.enable_itn);
    assert!(configuration.enable_punctuation);
    assert!(!configuration.enable_ddc);
    assert_eq!(configuration.boosting_table_id, "fixture-table");
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-key" && header.value == "synthetic-key"));
    assert!(!configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-app-key"));

    preferences.voice_input.doubao_auth_mode = "legacy".into();
    preferences.voice_input.asr_app_key = "synthetic-app".into();
    let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-app-key" && header.value == "synthetic-app"));
    assert!(configuration
        .headers
        .iter()
        .any(|header| header.name == "x-api-access-key"));
}

#[cfg(unix)]
#[test]
fn voice_provider_options_only_forwards_known_doubao_auth_modes() {
    let document = serde_json::json!({
        "preferences": {"voice_input": {
            "doubao_auth_mode": "legacy",
            "asr_app_key": "private-app-id",
            "asr_token": "private-token"
        }}
    });
    let result = super::voice_provider_options(&document);
    assert!(result.is_ok());
    let options = result.ok().expect("voice options should be valid");
    assert_eq!(
        options.get("doubao_auth_mode").and_then(|v| v.as_str()),
        Some("legacy")
    );
    assert!(options.get("asr_app_key").is_none());
    assert!(options.get("asr_token").is_none());

    let document = serde_json::json!({
        "preferences": {"voice_input": {"doubao_auth_mode": "unknown"}}
    });
    let result = super::voice_provider_options(&document);
    assert!(result.is_ok());
    let options = result.ok().expect("voice options should be valid");
    assert!(options.get("doubao_auth_mode").is_none());
}

#[cfg(unix)]
#[test]
fn voice_provider_options_bound_strings_by_utf8_bytes() {
    let multibyte = "界".repeat(200);
    let document = serde_json::json!({
        "preferences": {"voice_input": {
            "asr_model": multibyte,
            "capture_device": "x".repeat(600)
        }}
    });
    let options = super::voice_provider_options(&document).unwrap();
    let model = options
        .get("asr_model")
        .and_then(|value| value.as_str())
        .unwrap();
    let device = options
        .get("capture_device")
        .and_then(|value| value.as_str())
        .unwrap();

    assert_eq!(model.len(), 510);
    assert_eq!(model.chars().count(), 170);
    assert_eq!(device.len(), 512);
}

#[cfg(unix)]
#[test]
fn voice_preferences_refresh_keeps_transport_and_reads_latest_store_snapshot() {
    let root = tempfile::tempdir().unwrap();
    let store = super::PreferencesStore::new(root.path());
    let initial = store.load().unwrap();
    let mut preferences = initial.preferences;
    preferences.voice_input.asr_provider = "openai".into();
    let saved = store.save(initial.revision, preferences).unwrap();
    let document = serde_json::json!({
        "voice_provider_socket": "/fixture/voice.sock",
        "preferences": {"voice_input": {"asr_provider": "stale"}}
    });
    let refreshed = super::refresh_voice_preferences(document, &store).unwrap();
    assert_eq!(
        refreshed["preferences"]["voice_input"]["asr_provider"],
        "openai"
    );
    assert_eq!(refreshed["voice_provider_socket"], "/fixture/voice.sock");
    assert_eq!(saved.revision, store.load().unwrap().revision);
}

#[cfg(unix)]
#[test]
fn credential_tests_route_to_the_configured_provider_without_credentials() {
    let document = serde_json::json!({
        "online_provider_socket": "/fixture/online.sock",
        "translation_provider_socket": "/fixture/translation.sock",
        "voice_provider_socket": "/fixture/voice.sock",
    });
    assert_eq!(
        super::credential_provider_socket(&document, "ai.assistant"),
        Some(std::path::PathBuf::from("/fixture/online.sock"))
    );
    assert_eq!(
        super::credential_provider_socket(&document, "translation.niutrans"),
        Some(std::path::PathBuf::from("/fixture/translation.sock"))
    );
    assert_eq!(
        super::credential_provider_socket(&document, "voice.polish"),
        Some(std::path::PathBuf::from("/fixture/voice.sock"))
    );
    assert!(super::credential_provider_socket(&document, "unknown").is_none());
}

#[test]
fn second_launch_routes_are_taken_from_explicit_arguments() {
    use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};

    assert_eq!(
        super::launch_route_from_args(&["--route=emoji".into()]),
        Some(SurfaceRoute::Emoji)
    );
    assert_eq!(
        super::launch_route_from_args(&["--route=settings:about".into()])
            .and_then(|route| route.settings_category()),
        Some(SettingsCategory::About)
    );
    assert_eq!(
        super::launch_route_from_args(&["--route=../private".into()]),
        None
    );
    assert_eq!(super::launch_route_from_args(&["--other".into()]), None);
}

#[test]
fn dictionary_mutations_quiesce_but_reads_do_not() {
    assert!(super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "edit"})
    ));
    assert!(super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "import"})
    ));
    assert!(!super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "list"})
    ));
    assert!(!super::dictionary_action_requires_quiesce(
        &serde_json::json!({"operation": "export"})
    ));
}

#[test]
fn macos_restart_targets_the_input_method_bundle() {
    assert_eq!(
        super::macos_input_source_restart_args(),
        [
            "-n",
            "-b",
            "app.msime.client.preview.inputmethod",
            "--args",
            "--reregister-input-source",
        ]
    );
}

#[test]
fn settings_routes_select_a_page_the_shared_ui_accepts() {
    use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};
    // The route wins over the compatibility variable, and every category the
    // contract accepts survives the settings-page identifier filter.
    for category in SettingsCategory::ALL {
        let page =
            super::settings_page_from_route(Some(SurfaceRoute::Settings(Some(category))));
        assert_eq!(
            super::requested_settings_page(page.as_deref()),
            Some(category.as_str().to_owned()),
            "category {category:?} is not a usable settings page id"
        );
    }
    assert_eq!(
        super::settings_page_from_route(Some(SurfaceRoute::Settings(None))),
        None
    );
    assert_eq!(
        super::settings_page_from_route(Some(SurfaceRoute::Emoji)),
        None
    );
}

#[test]
fn requested_settings_page_only_accepts_a_plain_section_identifier() {
    assert_eq!(
        super::requested_settings_page(Some(" about ")),
        Some("about".into())
    );
    assert_eq!(
        super::requested_settings_page(Some("screen-keyboard")),
        Some("screen-keyboard".into())
    );
    assert_eq!(super::requested_settings_page(None), None);
    assert_eq!(super::requested_settings_page(Some("   ")), None);
    // Anything that could carry a path, a query or a script stays out of
    // the window the launcher is about to open.
    assert_eq!(super::requested_settings_page(Some("../etc")), None);
    assert_eq!(super::requested_settings_page(Some("About")), None);
    assert_eq!(super::requested_settings_page(Some("a?b=c")), None);
    assert_eq!(super::requested_settings_page(Some(&"a".repeat(33))), None);
}

#[test]
fn packaged_handwriting_model_only_accepts_an_existing_absolute_file() {
    let directory = tempfile::tempdir().unwrap();
    let model = directory.path().join("handwriting-zh_CN.model");
    std::fs::write(&model, b"synthetic").unwrap();
    let options = |value: String| serde_json::json!({ "handwriting_model": value }).to_string();

    // The host options win when they name a model that is actually there.
    assert_eq!(
        super::packaged_handwriting_model(&options(model.to_string_lossy().into_owned())),
        Some(model.clone())
    );

    // A relative or missing path is refused rather than handed to the
    // recognizer, so a stale setting cannot send strokes at something else.
    assert_eq!(
        super::packaged_handwriting_model(&options("model".into())),
        None
    );
    assert_eq!(
        super::packaged_handwriting_model(&options(
            directory
                .path()
                .join("absent.model")
                .to_string_lossy()
                .into_owned()
        )),
        None
    );
}

#[test]
fn typing_statistics_status_reports_file_availability_without_content() {
    let directory = tempfile::tempdir().unwrap();
    let store =
        msime_client_core::typing_statistics::TypingStatisticsStore::new(directory.path());
    let missing = super::typing_statistics_status(&store, store.load().unwrap())
        .ok()
        .unwrap();
    let missing_json = serde_json::to_value(missing).unwrap();
    assert_eq!(missing_json["availability"], "neverWritten");
    assert!(missing_json["lastWrittenMs"].is_null());
    assert_eq!(missing_json["statistics"]["enabled"], true);

    let disabled = store.set_enabled(false).unwrap();
    let ready = super::typing_statistics_status(&store, disabled)
        .ok()
        .unwrap();
    let ready_json = serde_json::to_value(ready).unwrap();
    assert_eq!(ready_json["availability"], "ready");
    assert!(ready_json["lastWrittenMs"].is_number());
    assert_eq!(ready_json["statistics"]["enabled"], false);
}

#[cfg(target_os = "linux")]
#[test]
fn panel_input_targets_are_isolated_by_surface() {
    let state = super::PanelInputState::default();
    let mut targets = state.0.lock().unwrap();
    targets.insert(
        "emoji-panel".into(),
        super::PanelInputTarget::X11("11".into()),
    );
    targets.insert(
        "keyboard-panel".into(),
        super::PanelInputTarget::X11("22".into()),
    );
    targets.remove("emoji-panel");
    assert!(targets.get("emoji-panel").is_none());
    assert!(matches!(
        targets.get("keyboard-panel"),
        Some(super::PanelInputTarget::X11(window)) if window == "22"
    ));
}

#[cfg(not(target_os = "windows"))]
#[test]
fn keyboard_does_not_accept_focus_but_editable_panels_do() {
    assert!(!super::panel_accepts_focus("keyboard-panel"));
    for label in [
        "handwriting-panel",
        "voice-panel",
        "emoji-panel",
        "cloud-clipboard-panel",
        "cloud-dictionary-panel",
    ] {
        assert!(super::panel_accepts_focus(label));
    }
}
#[test]
fn toolbar_stylesheet_command_errors_do_not_expose_paths() {
    let state = tempfile::tempdir().unwrap();
    let result =
        super::read_skin_toolbar_stylesheet_at(state.path().join("skins"), "../sample");
    let error = match result {
        Err(error) => error,
        Ok(_) => panic!("expected error"),
    };
    assert_eq!(
        serde_json::to_value(error).unwrap(),
        serde_json::json!({ "code": "storage" })
    );
}
#[test]
fn skin_image_command_contract_filters_non_images_and_paths() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let folder = root.join("sample");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(folder.join("skin.toml"), "schema_version = 1\nid = 'sample'\nname = 'Sample'\nversion = '1'\nbase = 'fluent'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n[candidate_window]\n[candidate_window.decoration]\n").unwrap();
    std::fs::write(folder.join("preview.png"), [0, 1, 255]).unwrap();
    std::fs::write(folder.join("font.woff2"), [0, 1, 255]).unwrap();
    std::fs::write(folder.join("toolbar.css"), b".sample {}").unwrap();
    assert!(matches!(
        super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"),
        Ok(None)
    ));
    let manifest = std::fs::read_to_string(folder.join("skin.toml")).unwrap();
    std::fs::write(
        folder.join("skin.toml"),
        format!("toolbar_stylesheet = 'toolbar.css'\n{manifest}"),
    )
    .unwrap();
    assert!(
        matches!(super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"), Ok(Some(css)) if css == ".sample {}")
    );
    let result = super::read_skin_image_at(root.clone(), "sample", "preview.png")
        .ok()
        .unwrap();
    let json = serde_json::to_value(result).unwrap();
    assert_eq!(json["contentType"], "image/png");
    assert_eq!(json["bytes"], serde_json::json!([0, 1, 255]));
    let font = super::read_skin_font_at(root.clone(), "sample", "font.woff2")
        .ok()
        .unwrap();
    let font_json = serde_json::to_value(font).unwrap();
    assert_eq!(font_json["contentType"], "font/woff2");
    assert_eq!(font_json["bytes"], serde_json::json!([0, 1, 255]));
    assert!(super::read_skin_font_at(root.clone(), "sample", "preview.png").is_err());
    assert!(super::read_skin_font_at(root.clone(), "sample", "../font.woff2").is_err());
    assert!(super::read_skin_font_at(root.clone(), "../sample", "font.woff2").is_err());
    assert!(super::read_skin_image_at(root.clone(), "sample", "toolbar.css").is_err());
    assert!(super::read_skin_image_at(root.clone(), "sample", "../preview.png").is_err());
    assert!(super::read_skin_image_at(root, "../sample", "preview.png").is_err());
}

#[test]
fn skin_catalog_response_uses_host_root_and_preserves_scan_results() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let folder = root.join("sample");
    std::fs::create_dir_all(&folder).unwrap();
    std::fs::write(
        folder.join("skin.toml"),
        r#"schema_version = 1
id = 'sample'
name = 'Sample'
version = '1'
base = 'fluent'
[supports]
layouts = ['vertical']
themes = ['light']
[candidate_window]
[candidate_window.decoration]
"#,
    )
    .unwrap();
    std::fs::create_dir(root.join("Bad")).unwrap();
    let result = serde_json::to_value(super::read_skin_catalog(root.clone())).unwrap();
    assert_eq!(result["directory"], root.to_string_lossy().as_ref());
    assert_eq!(result["packages"][0]["id"], "sample");
    assert_eq!(result["packages"].as_array().unwrap().len(), 1);
    assert_eq!(result["issues"].as_array().unwrap().len(), 1);
    assert_eq!(
        result["packages"][0]["layouts"],
        serde_json::json!(["vertical"])
    );
    assert_eq!(result["issues"][0]["folder"], "Bad");
    assert!(result.get("catalog").is_none());
}

#[test]
fn scanning_missing_skin_directory_does_not_create_it() {
    let state = tempfile::tempdir().unwrap();
    let root = state.path().join("skins");
    let result = super::read_skin_catalog(root.clone());
    assert!(result.catalog.packages.is_empty());
    assert!(result.catalog.issues.is_empty());
    assert!(!root.exists());
}

#[cfg(target_os = "linux")]
use super::*;

#[cfg(target_os = "linux")]
#[test]
fn linux_xdotool_geometry_requires_complete_numeric_shell_fields() {
    let geometry = "WINDOW=4194305\nX=120\nY=48\nWIDTH=1280\nHEIGHT=720\nSCREEN=1\n";
    assert_eq!(
        parse_xdotool_geometry(geometry),
        Some((120.0, 48.0, 1280.0, 720.0))
    );

    for malformed in [
        "X=120\nY=48\nWIDTH=1280\n",
        "X=120\nY=48\nWIDTH=1280\nHEIGHT=oops\n",
        "X=120\nY=48\nWIDTH=1280\nHEIGHT=720\nBROKEN",
    ] {
        assert_eq!(parse_xdotool_geometry(malformed), None);
    }
}

#[cfg(target_os = "linux")]
#[test]
fn linux_x11_panel_target_pid_matching_rejects_our_own_window() {
    assert!(x11_window_is_owned_by_process("4242\n", 4242));
    assert!(!x11_window_is_owned_by_process("4243\n", 4242));
    assert!(!x11_window_is_owned_by_process("not-a-pid\n", 4242));
    assert!(!x11_window_is_owned_by_process("", 4242));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_panel_text_uses_clipboard_for_non_ascii_on_keymap_backends() {
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::X11("11".into()),
        "你好😀"
    ));
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::Ydotool,
        "你好"
    ));
    assert!(!panel_text_requires_clipboard(
        &PanelInputTarget::Wayland,
        "你好😀"
    ));
    assert!(panel_text_requires_clipboard(
        &PanelInputTarget::Wayland,
        "line\nnext"
    ));
}

#[cfg(target_os = "linux")]
#[test]
fn linux_sway_target_and_geometry_walk_nested_and_floating_nodes() {
    let tree = serde_json::json!({
        "type": "root",
        "nodes": [{
            "type": "workspace",
            "id": 7,
            "rect": {"x": 10, "y": 20, "width": 1600, "height": 900},
            "nodes": [{
                "type": "con",
                "id": 42,
                "focused": true,
                "rect": {"x": 110, "y": 220, "width": 900, "height": 600}
            }],
            "floating_nodes": [{
                "type": "floating_con",
                "id": 99,
                "rect": {"x": 300, "y": 400, "width": 300, "height": 200}
            }]
        }]
    });

    assert_eq!(focused_sway_container(&tree), Some(42));
    assert_eq!(
        sway_rect_for_container(&tree, 42),
        Some((110.0, 220.0, 900.0, 600.0))
    );
    assert_eq!(
        sway_rect_for_container(&tree, 99),
        Some((300.0, 400.0, 300.0, 200.0))
    );
    assert_eq!(
        sway_workspace_for_container(&tree, 42, None),
        Some((10.0, 20.0, 1600.0, 900.0))
    );
    assert_eq!(sway_rect_for_container(&tree, 404), None);
    assert_eq!(sway_workspace_for_container(&tree, 404, None), None);
}

#[cfg(target_os = "linux")]
#[test]
fn linux_sway_workspace_does_not_leak_across_sibling_workspaces() {
    let tree = serde_json::json!({
        "type": "root",
        "nodes": [
            {"type": "workspace", "id": 1,
             "rect": {"x": 0, "y": 0, "width": 800, "height": 600},
             "nodes": [{"id": 11, "rect": {"x": 0, "y": 0, "width": 800, "height": 600}}]},
            {"type": "workspace", "id": 2,
             "rect": {"x": 800, "y": 0, "width": 800, "height": 600},
             "nodes": [{"id": 22, "rect": {"x": 800, "y": 0, "width": 800, "height": 600}}]}
        ]
    });

    assert_eq!(
        sway_workspace_for_container(&tree, 22, None),
        Some((800.0, 0.0, 800.0, 600.0))
    );
    assert_eq!(sway_workspace_for_container(&tree, 33, None), None);
}

#[cfg(target_os = "linux")]
#[test]
fn runtime_options_sync_replaces_preferences_atomically() {
    let directory = tempfile::tempdir().expect("temporary directory");
    let path = directory.path().join("runtime-options.json");
    let document = serde_json::json!({
        "api_version": 1,
        "resources": "/resources",
        "preferences": {"candidate_page_size": 5}
    });
    std::fs::write(&path, serde_json::to_vec(&document).unwrap()).unwrap();
    let state = RuntimeOptionsState {
        path: Some(path.clone()),
        document: Arc::new(Mutex::new(document)),
    };
    let mut preferences = Preferences::default();
    preferences.candidate_page_size = 9;
    sync_runtime_options(&state, &preferences).unwrap();
    let updated: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(updated["preferences"]["candidate_page_size"], 9);
}

//! Versioned, thread-confined C interface for native IME hosts.
//! A handle registry rejects stale and wrong-thread handles without dereferencing them.

// The workspace denies unsafe code; this crate is the C ABI native hosts link against, so every handle,
// pointer and string it accepts crosses a boundary the compiler cannot check.
// The exemption is stated here rather than left implicit by opting out of
// the workspace lint table, which would also silently drop every other lint
// the workspace adds later.
#![allow(unsafe_code)]

use msime_client_core::ai::AiSuggestionRequest;
use msime_client_core::dictionary::access::DictionaryAccess;
use msime_client_core::host_surface::{HostCapabilities, HostPlatform, SurfaceRoute};
pub mod cloud_clipboard;
pub mod cloud_dictionary;
pub mod system_fonts;
use msime_client_core::preferences::{
    InputScheme, Preferences, PreferencesSnapshot, PreferencesStore, ShuangpinProfile,
    TouchKeyboardLayout,
};
use msime_client_core::punctuation::{
    route as punctuation_route, PunctuationContext, PunctuationRoute,
};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_client_core::typing_statistics::{TypingSource, TypingStatisticsStore};
use msime_client_core::voice::doubao_frame::{
    audio_frame, decode_error_code, decode_json_frame, start_frame,
};
use msime_client_core::voice::VoiceSessionState;
use msime_engine_bridge::{CandidateEdge, Command, EngineOptions, Session};
use msime_input_runtime::HandwritingQuery;
#[cfg(unix)]
use msime_input_runtime::UnixSocketProvider;
use msime_input_runtime::{
    Action, AiAssistantProviderConfig, CandidateId, CharacterWidth, NineKeySpellingId, OnlineQuery,
    Reranker, Runtime, SentenceModel, Transition,
};
#[cfg(unix)]
use msime_input_runtime::{EmojiPanelQuery, TranslationQuery};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
// Only the Unix socket streaming entry point takes raw callback context.
#[cfg(unix)]
use std::ffi::c_void;
use std::panic::{catch_unwind, AssertUnwindSafe};
mod dictionary;
mod doubao_auth;
pub use doubao_auth::msime_client_doubao_auth_headers;
mod learned_translation;
mod niutrans_translation;
mod tencent_translation;
pub use dictionary::{
    dictionary_request_json, msime_client_dictionary, msime_client_dictionary_validate,
    msime_client_personal_dictionary_sync, personal_dictionary_request_json,
};
mod dictionary_snapshot;
pub use dictionary_snapshot::{
    msime_client_snapshot_discard, msime_client_snapshot_prepare, msime_client_snapshot_version,
};

/// Names of the audio capture devices the Engine can record from.
///
/// The desktop shell depends on this crate, not on the Engine bridge, so the
/// bridge is reached through here the same way the handwriting recognizer is.
/// Names are display strings from the audio backend and carry no user data.
pub fn voice_capture_device_names() -> Vec<String> {
    msime_engine_bridge::capture_device_names()
}

/// Capture endpoint identities paired with labels. Neither belongs in logs.
pub fn voice_capture_devices() -> Vec<(String, String)> {
    msime_engine_bridge::capture_devices()
        .into_iter()
        .map(|device| (device.id, device.label))
        .collect()
}

/// Capture bounded mono 16 kHz PCM for a platform host.
pub fn voice_capture_pcm(milliseconds: u32) -> Result<Vec<f32>, &'static str> {
    if !(1..=60_000).contains(&milliseconds) {
        return Err("invalid voice capture duration");
    }
    let samples = msime_engine_bridge::capture_audio(milliseconds);
    if samples.is_empty() {
        return Err("voice capture unavailable");
    }
    Ok(samples)
}

/// Run the optional offline Engine handwriting recognizer for a panel host.
/// The caller must provide a trusted absolute model path; strokes are copied
/// before crossing the C++ bridge. The shared panel uses a 420 by 420 canvas,
/// which is also the coordinate space passed to the Engine. This path needs no
/// provider socket, so every host can use it.
pub fn handwriting_local_candidates(
    model_path: &str,
    query: &HandwritingQuery,
) -> Result<Vec<String>, &'static str> {
    if !std::path::Path::new(model_path).is_absolute() {
        return Err("model path must be absolute");
    }
    engine_handwriting_candidates(model_path, query, 420.0, 420.0)
}

#[cfg(not(any(target_os = "android", target_env = "ohos")))]
fn engine_handwriting_candidates(
    model_path: &str,
    query: &HandwritingQuery,
    width: f32,
    height: f32,
) -> Result<Vec<String>, &'static str> {
    let strokes = query
        .strokes
        .iter()
        .map(|stroke| stroke.iter().map(|point| (point.x, point.y)).collect())
        .collect::<Vec<Vec<(f32, f32)>>>();
    msime_engine_bridge::handwriting_recognize(model_path, &strokes, width, height)
        .map_err(|_| "local handwriting recognizer unavailable")
}

#[cfg(any(target_os = "android", target_env = "ohos"))]
fn engine_handwriting_candidates(
    _model_path: &str,
    _query: &HandwritingQuery,
    _width: f32,
    _height: f32,
) -> Result<Vec<String>, &'static str> {
    // Android injects ML Kit Digital Ink through HandwritingRecognizer. Keeping
    // this boundary unavailable prevents zinnia and its model path from becoming
    // an unused second recognizer in the IME process. HarmonyOS is the same case:
    // its build turns MSIME_ENGINE_BRIDGE_HANDWRITING off, so the Engine symbol
    // is not there to call.
    Err("local handwriting recognizer unavailable")
}

thread_local! {
    static SESSIONS: RefCell<HashMap<u64, HostSession>> = RefCell::new(HashMap::new());
}

struct HostSession {
    runtime: Runtime,
    options: EngineOptions,
    applied: Preferences,
    requested: Option<PreferencesSnapshot>,
    punctuation_override: Option<bool>,
    paired_punctuation_override: Option<bool>,
    punctuation_lock_override: Option<u8>,
    english_mode: bool,
    page_size_override: Option<u8>,
    nine_key_override: Option<bool>,
    voice: VoiceSessionState,
    // Declared after runtime so the Engine is dropped before releasing access.
    _dictionary_access: DictionaryAccess,
}

/// Local input modes are preference-controlled, but their backing dictionaries are
/// immutable runtime resources. Keep a missing optional resource from turning a
/// trigger key into a swallowed event: the Engine must see that mode disabled until
/// the complete resource set is present.
fn apply_local_mode_resource_gates(options: &mut EngineOptions) {
    let resources = std::path::Path::new(&options.resources);
    let has_emoji_catalog = resources.join("others.db").is_file();
    let has_english_dictionary = resources.join("english.db").is_file();
    let has_japanese_model = resources.join("dict_japanese.dat").is_file();
    options.local_emoji &= has_emoji_catalog;
    options.local_kaomoji &= has_emoji_catalog;
    options.local_temporary_english &= has_english_dictionary;
    options.local_temporary_japanese &= has_japanese_model;
}

impl HostSession {
    fn ai_provider_config(&self) -> Option<AiAssistantProviderConfig> {
        let preferences = self
            .requested
            .as_ref()
            .map(|snapshot| &snapshot.preferences)
            .unwrap_or(&self.applied);
        let ai = &preferences.ai_assistant;
        ai.enabled.then(|| AiAssistantProviderConfig {
            enabled: true,
            provider: ai.provider.clone(),
            model: ai.model.clone(),
            endpoint: ai.endpoint.clone(),
            candidate_limit: ai.candidate_limit,
            prompt_id: ai.prompt_id.clone(),
            prompt: ai.prompt.clone(),
            prompt_custom_1: ai.prompt_custom_1.clone(),
            prompt_custom_2: ai.prompt_custom_2.clone(),
            prompt_custom_3: ai.prompt_custom_3.clone(),
        })
    }
    fn ai_query_is_current(&self, query: &OnlineQuery) -> bool {
        self.ai_provider_config()
            .is_some_and(|config| query.ai_assistant.as_ref() == Some(&config))
    }
    fn cloud_candidates_enabled(&self) -> bool {
        self.applied.cloud_candidates
            && self
                .requested
                .as_ref()
                .is_none_or(|snapshot| snapshot.preferences.cloud_candidates)
    }
    fn apply_pending(&mut self) -> Result<(), String> {
        if self.runtime.is_idle() {
            if let Some(size) = self.page_size_override {
                self.runtime
                    .set_page_size(size)
                    .map_err(|e| e.to_string())?;
            }
        }
        let Some(snapshot) = &self.requested else {
            return Ok(());
        };
        if snapshot.preferences == self.applied || !self.runtime.is_idle() {
            return Ok(());
        }
        let mut options = self.options.clone();
        options.scheme = scheme_code(snapshot.preferences.scheme);
        options.shuangpin_profile = profile_code(snapshot.preferences.shuangpin_profile);
        options.shuangpin_preedit_uses_raw = snapshot.preferences.shuangpin_preedit_uses_raw;
        options.learning = snapshot.preferences.learning;
        options.autocorrect_transposition =
            snapshot.preferences.quanpin_autocorrect_transposition();
        options.autocorrect_neighbor = snapshot.preferences.quanpin_autocorrect_neighbor();
        options.fuzzy_pinyin_rules = snapshot.preferences.fuzzy_pinyin.active_rules();
        options.wubi_mixed_pinyin = snapshot.preferences.wubi_mixed_pinyin;
        options.frequency_mode = snapshot.preferences.frequency.mode.as_str().into();
        options.frequency_trigger_count = snapshot.preferences.frequency.trigger_count;
        options.frequency_linear_step = snapshot.preferences.frequency.linear_step;
        options.mixed_english = snapshot.preferences.mixed_input.english;
        options.english_minimum_prefix = snapshot.preferences.mixed_input.minimum_prefix;
        options.mixed_emoji = snapshot.preferences.mixed_input.emoji;
        options.mixed_kaomoji = snapshot.preferences.mixed_input.kaomoji;
        options.local_unicode = snapshot.preferences.local_modes.unicode;
        options.local_date_time = snapshot.preferences.local_modes.date_time;
        options.local_quick_phrase = snapshot.preferences.local_modes.quick_phrase;
        options.local_emoji = snapshot.preferences.local_modes.emoji;
        options.local_kaomoji = snapshot.preferences.local_modes.kaomoji;
        options.local_super_jianpin = snapshot.preferences.local_modes.super_jianpin;
        options.local_temporary_english = snapshot.preferences.local_modes.temporary_english;
        options.local_temporary_japanese = snapshot.preferences.local_modes.temporary_japanese;
        // Unconditional, because `Runtime::crop_alternative_readings` runs whether or not a model is
        // attached: the host always shows one whole-sentence reading. Asking for the rest only ever
        // gives it more to choose from, and even with no model the engine's own pick among them is
        // better than the one it makes when it searches without alternatives.
        options.sentence_alternatives = true;
        apply_local_mode_resource_gates(&mut options);
        let helpcode = snapshot.preferences.active_helpcode();
        options.helpcode = helpcode.enabled;
        options.show_helpcode = helpcode.show_in_candidate_window;
        options.helpcode_schema = helpcode.schema.as_str().into();
        options.chinese_punctuation = snapshot.preferences.chinese_punctuation;
        options.paired_punctuation = snapshot.preferences.paired_punctuation;
        options.punctuation_lock = match snapshot.preferences.punctuation_lock {
            msime_client_core::preferences::PunctuationLock::Follow => 0,
            msime_client_core::preferences::PunctuationLock::Chinese => 1,
            msime_client_core::preferences::PunctuationLock::English => 2,
        };
        // Build and validate first; errors leave the original session usable.
        let mut engine = Session::new(&options).map_err(|e| e.to_string())?;
        if let Some(enabled) = self.punctuation_override {
            engine
                .set_chinese_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
        }
        if let Some(enabled) = self.paired_punctuation_override {
            engine
                .set_paired_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
        }
        if let Some(lock) = self.punctuation_lock_override {
            engine
                .set_punctuation_lock(lock)
                .map_err(|e| e.to_string())?;
        }
        let layout_changed =
            snapshot.preferences.touch_keyboard_layout != self.applied.touch_keyboard_layout;
        let next_nine_key_override = if options.scheme == 0 && !layout_changed {
            self.nine_key_override
        } else {
            None
        };
        let nine_key_mode = options.scheme == 0
            && next_nine_key_override.unwrap_or(matches!(
                snapshot.preferences.touch_keyboard_layout,
                TouchKeyboardLayout::NineKey
            ));
        if nine_key_mode {
            engine
                .set_nine_key_enabled(true)
                .map_err(|e| e.to_string())?;
        }
        engine
            .set_dedicated_english(self.english_mode)
            .map_err(|e| e.to_string())?;
        self.runtime
            .replace_engine_with_touch_layout(
                engine,
                self.page_size_override
                    .unwrap_or(snapshot.preferences.candidate_page_size),
                snapshot.preferences.touch_keyboard_layout,
            )
            .map_err(|e| e.to_string())?;
        self.options = options;
        self.applied = snapshot.preferences.clone();
        self.nine_key_override = next_nine_key_override;
        Ok(())
    }

    fn complete_transition(&mut self, mut result: Transition) -> Transition {
        if let Err(error) = self.apply_pending() {
            let prior = result.diagnostic.take().unwrap_or_default();
            result.diagnostic = Some(
                format!("{prior} Preferences update deferred: {error}")
                    .trim()
                    .to_owned(),
            );
        }
        // A replacement changes the view generation, never the completed commit.
        if result.view.character_width == CharacterWidth::Fullwidth {
            if let Some(c) = result.commit.as_mut() {
                *c = c
                    .chars()
                    .map(|x| {
                        if x == ' ' {
                            '\u{3000}'
                        } else if ('!'..='~').contains(&x) {
                            char::from_u32(x as u32 + 0xfee0).unwrap()
                        } else {
                            x
                        }
                    })
                    .collect();
            }
        }
        result.view = self.runtime.view();
        result
    }

    fn update(&mut self, snapshot: PreferencesSnapshot) -> Result<Value, String> {
        if snapshot.format_version != 1 {
            return Err("unsupported preferences format".into());
        }
        snapshot.preferences.validate().map_err(|e| e.to_string())?;
        if let Some(previous) = &self.requested {
            if snapshot.revision < previous.revision
                || (snapshot.revision == previous.revision && snapshot != *previous)
            {
                return Err("stale or conflicting preferences revision".into());
            }
        }
        self.requested = Some(snapshot);
        self.apply_pending()?;
        let snapshot = self.requested.as_ref().expect("requested snapshot exists");
        Ok(
            json!({ "revision": snapshot.revision, "deferred": snapshot.preferences != self.applied, "view": self.runtime.view(), "floating_toolbar": { "enabled": snapshot.preferences.floating_toolbar.enabled, "english_mode": snapshot.preferences.floating_toolbar.english_mode, "scale_percent": snapshot.preferences.floating_toolbar.scale_percent, "font_size": snapshot.preferences.floating_toolbar.font_size, "fullwidth": snapshot.preferences.floating_toolbar.fullwidth, "punctuation": snapshot.preferences.floating_toolbar.punctuation, "character_set": snapshot.preferences.floating_toolbar.character_set, "emoji": snapshot.preferences.floating_toolbar.emoji, "screen_keyboard": snapshot.preferences.floating_toolbar.screen_keyboard, "settings": snapshot.preferences.floating_toolbar.settings } }),
        )
    }
}

fn profile_code(profile: ShuangpinProfile) -> u8 {
    match profile {
        ShuangpinProfile::Xiaohe => 0,
        ShuangpinProfile::Ziranma => 1,
        ShuangpinProfile::Shoudao => 2,
        ShuangpinProfile::Microsoft => 3,
    }
}

fn scheme_code(scheme: InputScheme) -> u8 {
    match scheme {
        InputScheme::Quanpin => 0,
        InputScheme::Shuangpin => 1,
        InputScheme::Wubi => 2,
        InputScheme::Japanese => 3,
    }
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct HostOptions {
    api_version: u32,
    resources: String,
    user_data: String,
    cache: String,
    dictionaries: String,
    preferences: Preferences,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    preferences_directory: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    clipboard_history_path: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    online_provider_socket: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    translation_provider_socket: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cloud_dictionary_provider_socket: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    cloud_clipboard_provider_socket: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    voice_provider_socket: Option<String>,
    /// Absolute path to the candidate reranking model, when it is installed as its own artifact
    /// rather than placed beside the dictionaries.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    sentence_model: Option<String>,
}

impl HostOptions {
    fn into_engine_options(self) -> EngineOptions {
        let helpcode = self.preferences.active_helpcode();
        let mut options = EngineOptions {
            resources: self.resources,
            user_data: self.user_data,
            cache: self.cache,
            dictionaries: self.dictionaries,
            scheme: scheme_code(self.preferences.scheme),
            shuangpin_profile: profile_code(self.preferences.shuangpin_profile),
            shuangpin_preedit_uses_raw: self.preferences.shuangpin_preedit_uses_raw,
            learning: self.preferences.learning,
            autocorrect_transposition: self.preferences.quanpin_autocorrect_transposition(),
            autocorrect_neighbor: self.preferences.quanpin_autocorrect_neighbor(),
            fuzzy_pinyin_rules: self.preferences.fuzzy_pinyin.active_rules(),
            wubi_mixed_pinyin: self.preferences.wubi_mixed_pinyin,
            frequency_mode: self.preferences.frequency.mode.as_str().into(),
            frequency_trigger_count: self.preferences.frequency.trigger_count,
            frequency_linear_step: self.preferences.frequency.linear_step,
            mixed_english: self.preferences.mixed_input.english,
            english_minimum_prefix: self.preferences.mixed_input.minimum_prefix,
            mixed_emoji: self.preferences.mixed_input.emoji,
            mixed_kaomoji: self.preferences.mixed_input.kaomoji,
            local_unicode: self.preferences.local_modes.unicode,
            local_date_time: self.preferences.local_modes.date_time,
            local_quick_phrase: self.preferences.local_modes.quick_phrase,
            local_emoji: self.preferences.local_modes.emoji,
            local_kaomoji: self.preferences.local_modes.kaomoji,
            local_super_jianpin: self.preferences.local_modes.super_jianpin,
            local_temporary_english: self.preferences.local_modes.temporary_english,
            local_temporary_japanese: self.preferences.local_modes.temporary_japanese,
            sentence_alternatives: true,
            helpcode: helpcode.enabled,
            show_helpcode: helpcode.show_in_candidate_window,
            helpcode_schema: helpcode.schema.as_str().into(),
            chinese_punctuation: self.preferences.chinese_punctuation,
            paired_punctuation: self.preferences.paired_punctuation,
            punctuation_lock: match self.preferences.punctuation_lock {
                msime_client_core::preferences::PunctuationLock::Follow => 0,
                msime_client_core::preferences::PunctuationLock::Chinese => 1,
                msime_client_core::preferences::PunctuationLock::English => 2,
            },
        };
        apply_local_mode_resource_gates(&mut options);
        options
    }
}

/// Bootstrap a new host using the reviewed desktop data and Engine-owned replay.
/// Call only while all sessions using state_root are stopped. Does not activate it.
pub fn prepare_host_configuration(
    resources: &std::path::Path,
    state_root: &std::path::Path,
) -> Result<String, Box<dyn std::error::Error>> {
    let resources = std::fs::canonicalize(resources)?;
    let specification: ResourceSet = serde_json::from_str(include_str!(
        "../../../resources/desktop-dictionary.lock.json"
    ))?;
    ResourceStore::new(&resources).verify(&resources, &specification)?;
    let state_root = std::path::absolute(state_root)?;
    let prepared = msime_engine_bridge::prepare_options(
        resources.to_str().ok_or("non-UTF-8 resource path")?,
        state_root
            .join("user")
            .to_str()
            .ok_or("non-UTF-8 state path")?,
        state_root
            .join("cache")
            .to_str()
            .ok_or("non-UTF-8 cache path")?,
        &specification.generation()?,
    )?;
    let preference_store = PreferencesStore::new(&state_root);
    let snapshot = preference_store.load()?;
    #[cfg(windows)]
    let snapshot = migrate_windows_legacy_mixed_input(&preference_store, &state_root, snapshot)?;
    let preferences = snapshot.preferences;
    Ok(serde_json::to_string_pretty(&HostOptions {
        api_version: 1,
        resources: prepared.resources,
        user_data: prepared.user_data,
        cache: prepared.cache,
        dictionaries: prepared.dictionaries,
        preferences,
        preferences_directory: Some(
            state_root
                .to_str()
                .ok_or("non-UTF-8 state path")?
                .to_owned(),
        ),
        clipboard_history_path: None,
        online_provider_socket: None,
        translation_provider_socket: None,
        cloud_dictionary_provider_socket: None,
        cloud_clipboard_provider_socket: None,
        voice_provider_socket: None,
        // Written only when a model has actually been installed as its own artifact; a host that
        // places one beside the dictionaries needs no configuration.
        sentence_model: None,
    })?)
}

/// Import the mixed-input controls from the Windows installer's legacy TOML
/// once, before the shared JSON preference file exists. The installer still
/// carries this file for the TSF compatibility surface, and existing users
/// must not lose those choices when the shared Tauri/Engine store is created.
/// A present JSON store always wins; malformed or out-of-range legacy values
/// are ignored individually so a damaged optional config cannot block startup.
#[cfg(windows)]
fn migrate_windows_legacy_mixed_input(
    store: &PreferencesStore,
    state_root: &Path,
    snapshot: PreferencesSnapshot,
) -> Result<PreferencesSnapshot, Box<dyn std::error::Error>> {
    if state_root.join("preferences.json").try_exists()? {
        return Ok(snapshot);
    }
    let path = state_root.join("config.toml");
    let Ok(document) = std::fs::read_to_string(path) else {
        return Ok(snapshot);
    };
    let mut preferences = snapshot.preferences.clone();
    if !apply_windows_legacy_mixed_input(&document, &mut preferences) {
        return Ok(snapshot);
    }
    Ok(store.save(snapshot.revision, preferences)?)
}

#[cfg_attr(not(windows), allow(dead_code))]
fn apply_windows_legacy_mixed_input(document: &str, preferences: &mut Preferences) -> bool {
    let document = match document.parse::<toml::Table>() {
        Ok(document) => document,
        Err(_) => {
            return false;
        }
    };
    let Some(general) = document.get("general").and_then(toml::Value::as_table) else {
        return false;
    };
    let mut changed = false;
    if let Some(value) = general
        .get("cn_en_mixed_input")
        .and_then(toml::Value::as_bool)
    {
        preferences.mixed_input.english = value;
        changed = true;
    }
    if let Some(value) = general
        .get("cn_en_mixed_input_min_chars")
        .and_then(toml::Value::as_integer)
        .and_then(|value| u8::try_from(value).ok())
        .filter(|value| (1..=8).contains(value))
    {
        preferences.mixed_input.minimum_prefix = value;
        changed = true;
    }
    if let Some(value) = general
        .get("emoji_mixed_input")
        .and_then(toml::Value::as_bool)
    {
        preferences.mixed_input.emoji = value;
        changed = true;
    }
    if let Some(value) = general
        .get("kaomoji_mixed_input")
        .and_then(toml::Value::as_bool)
    {
        preferences.mixed_input.kaomoji = value;
        changed = true;
    }
    changed
}

/// Edit only after every participating host has destroyed its sessions.
/// Busy is retryable without cancelling any composition. The host must recreate
/// sessions after success; no native/Tauri management command is exposed yet.
/// Engine diagnostics are deliberately not returned: they may include user text.
pub fn edit_personal_dictionary(
    options: &EngineOptions,
    previous: Option<&msime_engine_bridge::DictionaryEntry>,
    replacement: Option<&msime_engine_bridge::DictionaryEntry>,
    request_id: &str,
) -> Result<(), &'static str> {
    let _access = DictionaryAccess::try_maintenance(
        std::path::Path::new(&options.user_data),
        std::path::Path::new(&options.dictionaries),
    )
    .map_err(|_| "dictionary access unavailable")?
    .ok_or("dictionary maintenance busy")?;
    if request_id.is_empty() {
        return Err("dictionary request id required");
    }
    msime_engine_bridge::dictionary_edit(options, previous, replacement, request_id)
        .map_err(|_| "dictionary edit rejected")
}

/// A host-owned view of one entry in the verified local Emoji catalog.
#[derive(Clone, Debug, Serialize)]
pub struct LocalEmojiCatalogItem {
    pub text: String,
    pub annotation: String,
    pub group: String,
}

#[derive(Clone, Debug, Serialize)]
pub struct LocalEmojiCatalogSlice {
    pub items: Vec<LocalEmojiCatalogItem>,
    pub next_offset: usize,
    pub complete: bool,
}

/// Read catalog rows without collapsing equal text from distinct categories.
// Not unix-gated: the bodies only call the engine bridge, which builds on
// Windows too (its build.rs has explicit Windows branches). The gate was a
// porting gap, and it left the Windows desktop falling back to the compact
// built-in catalog - 97 emoji against the several thousand rows in others.db -
// behind a permanent "catalog failed to load" banner.
pub fn local_emoji_catalog_slice(
    resources: &str,
    category: &str,
    offset: usize,
    limit: u16,
) -> Result<LocalEmojiCatalogSlice, &'static str> {
    if !std::path::Path::new(resources).is_absolute() {
        return Err("resources path must be absolute");
    }
    if limit == 0 || limit > 4096 {
        return Err("invalid local emoji page size");
    }
    msime_engine_bridge::emoji_catalog_slice(resources, "", category, "", offset, limit, "")
        .map(|page| LocalEmojiCatalogSlice {
            items: page
                .items
                .into_iter()
                .map(|item| LocalEmojiCatalogItem {
                    text: item.text,
                    annotation: item.annotation,
                    group: item.group,
                })
                .collect(),
            next_offset: page.next_offset,
            complete: page.complete,
        })
        .map_err(|_| "local emoji catalog unavailable")
}

#[derive(Clone, Debug, Serialize)]
pub struct LocalSymbolCatalogGroup {
    pub parent: String,
    pub title: String,
    pub items: Vec<LocalEmojiCatalogItem>,
}

/// Preserve Engine-owned symbol parent categories and subgroup order.
pub fn local_symbol_catalog(resources: &str) -> Result<Vec<LocalSymbolCatalogGroup>, &'static str> {
    if !std::path::Path::new(resources).is_absolute() {
        return Err("resources path must be absolute");
    }
    let groups = msime_engine_bridge::emoji_symbol_groups(resources)
        .map_err(|_| "local symbol catalog unavailable")?;
    let mut result = Vec::new();
    let mut remaining_pages = 256usize;
    for group in groups {
        let mut items = Vec::new();
        let mut offset = 0usize;
        loop {
            if remaining_pages == 0 {
                return Err("local symbol catalog exceeds limit");
            }
            remaining_pages -= 1;
            let page = msime_engine_bridge::emoji_catalog_slice(
                resources,
                "",
                "symbols",
                &group.title,
                offset,
                512,
                &group.parent,
            )
            .map_err(|_| "local symbol catalog unavailable")?;
            items.extend(page.items.into_iter().map(|item| LocalEmojiCatalogItem {
                text: item.text,
                annotation: item.annotation,
                group: item.group,
            }));
            if page.complete {
                break;
            }
            if page.next_offset <= offset {
                return Err("local symbol catalog cursor did not advance");
            }
            offset = page.next_offset;
        }
        result.push(LocalSymbolCatalogGroup {
            parent: group.parent,
            title: group.title,
            items,
        });
    }
    Ok(result)
}

/// Read one bounded page from the Engine-owned `others.db` catalog.
pub fn local_emoji_catalog_page(
    resources: &str,
    search: &str,
    category: &str,
    offset: usize,
    limit: u16,
) -> Result<Vec<LocalEmojiCatalogItem>, &'static str> {
    if !std::path::Path::new(resources).is_absolute() {
        return Err("resources path must be absolute");
    }
    if limit == 0 || limit > 4096 {
        return Err("invalid local emoji page size");
    }
    msime_engine_bridge::emoji_catalog_page(resources, search, category, offset, limit)
        .map(|items| {
            items
                .into_iter()
                .map(|item| LocalEmojiCatalogItem {
                    text: item.text,
                    annotation: item.annotation,
                    group: item.group,
                })
                .collect()
        })
        .map_err(|_| "local emoji catalog unavailable")
}

fn response(operation: impl FnOnce() -> Result<Value, String>) -> *mut c_char {
    let value = match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(Ok(value)) => json!({ "ok": true, "value": value }),
        Ok(Err(error)) => json!({ "ok": false, "error": error }),
        Err(_) => json!({ "ok": false, "error": "internal runtime failure" }),
    };
    // JSON escapes embedded NUL bytes, so this cannot contain an interior NUL.
    CString::new(value.to_string())
        .expect("JSON contains no NUL")
        .into_raw()
}

fn with_session(
    handle: u64,
    action: impl FnOnce(&mut HostSession) -> Result<Value, String>,
) -> Result<Value, String> {
    SESSIONS.with(|sessions| {
        let mut sessions = sessions
            .try_borrow_mut()
            .map_err(|_| "reentrant host call")?;
        let runtime = sessions
            .get_mut(&handle)
            .ok_or("unknown session or wrong thread")?;
        action(runtime)
    })
}

fn dispatch(handle: u64, action: Action) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            let result = session
                .runtime
                .dispatch(action)
                .map_err(|e| e.to_string())?;
            let result = session.complete_transition(result);
            serde_json::to_value(result).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_abi_version() -> u32 {
    2
}

/// Resolve display font families using the same adapter as the shared preview.
/// # Safety
/// `value` points to `length` readable bytes containing a JSON string array.
/// The returned response must be released with `msime_client_string_free`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_resolve_font_families(
    value: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if value.is_null() || length > 32 * 1024 {
            return Err("font_family".into());
        }
        // SAFETY: guaranteed by the caller contract; size checked above.
        let bytes = unsafe { std::slice::from_raw_parts(value, length) };
        let names: Vec<String> = serde_json::from_slice(bytes).map_err(|_| "font_family")?;
        let resolved = system_fonts::resolve_css_families(names).map_err(str::to_owned)?;
        Ok(json!(resolved))
    })
}

/// Resolve a shared surface route so a native host launches the shared shell by
/// name instead of hardcoding window labels. Returns the canonical route plus
/// the panel label, query and geometry, or an error for an unknown route.
/// # Safety
/// `value` points to `length` readable UTF-8 bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_parse_surface_route(
    value: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if value.is_null() || length > 1024 {
            return Err("invalid surface route buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(value, length) };
        let text = std::str::from_utf8(bytes).map_err(|_| "invalid surface route encoding")?;
        let route = SurfaceRoute::parse(text).map_err(|e| e.to_string())?;
        let mut document = json!({ "route": route.as_arg(), "surface": route });
        if let Some(panel) = route.panel() {
            document["panel"] = json!({
                "label": panel.label,
                "query": panel.query,
                "title": panel.title,
                "width": panel.width,
                "height": panel.height,
            });
        }
        Ok(document)
    })
}

/// Describe what the named host can do, so the shared UI renders from injected
/// capabilities instead of sniffing the user agent.
/// # Safety
/// `platform` points to `length` readable UTF-8 bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_host_capabilities(
    platform: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if platform.is_null() || length > 64 {
            return Err("invalid host platform buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(platform, length) };
        let text = std::str::from_utf8(bytes).map_err(|_| "invalid host platform encoding")?;
        let platform = HostPlatform::parse(text).map_err(|e| e.to_string())?;
        serde_json::to_value(HostCapabilities::for_platform(platform)).map_err(|e| e.to_string())
    })
}

/// Verify packaged resources and prepare an isolated new host. No live sessions
/// may use the state root while this runs. Returns a HostOptions object.
/// # Safety
/// `options` points to `length` readable UTF-8 JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_prepare_host(
    options: *const u8,
    length: usize,
) -> *mut c_char {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Bootstrap {
        resources: String,
        state_root: String,
    }
    response(|| {
        if options.is_null() || length > 16384 {
            return Err("invalid bootstrap buffer".into());
        }
        // SAFETY: guaranteed by the caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(options, length) };
        let options: Bootstrap =
            serde_json::from_slice(bytes).map_err(|_| "invalid bootstrap document")?;
        let resources = std::path::Path::new(&options.resources);
        let state = std::path::Path::new(&options.state_root);
        if !resources.is_absolute() || !state.is_absolute() {
            return Err("bootstrap paths must be absolute".into());
        }
        let document = prepare_host_configuration(resources, state).map_err(|e| e.to_string())?;
        serde_json::from_str(&document).map_err(|e| e.to_string())
    })
}

/// Load the shared store on a worker thread; no session handle is accessed.
/// # Safety
/// `directory` points to `length` readable UTF-8 bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_load_preferences(
    directory: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if directory.is_null() || length > 16384 {
            return Err("invalid preferences directory buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(directory, length) };
        let directory =
            std::str::from_utf8(bytes).map_err(|_| "invalid preferences directory encoding")?;
        if !std::path::Path::new(directory).is_absolute() {
            return Err("preferences directory must be absolute".into());
        }
        let snapshot = PreferencesStore::new(directory)
            .load()
            .map_err(|e| e.to_string())?;
        serde_json::to_value(snapshot).map_err(|e| e.to_string())
    })
}

/// Read or update private aggregate typing statistics without retaining submitted text.
/// # Safety
/// `request` points to `length` readable JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_typing_statistics(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Request {
        directory: String,
        action: StatisticsAction,
    }
    #[derive(Deserialize)]
    #[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
    enum StatisticsAction {
        Load,
        Record {
            text: String,
            source: TypingSource,
            day: String,
        },
        SetEnabled {
            enabled: bool,
        },
        Reset,
    }
    response(|| {
        if request.is_null() || length > 65_536 {
            return Err("invalid typing statistics buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let request: Request = serde_json::from_slice(bytes)
            .map_err(|_| "invalid typing statistics request".to_owned())?;
        if request.directory.len() > 16_384
            || !std::path::Path::new(&request.directory).is_absolute()
        {
            return Err("invalid typing statistics directory".into());
        }
        let store = TypingStatisticsStore::new(request.directory);
        match request.action {
            StatisticsAction::Load => {
                serde_json::to_value(store.load().map_err(|error| error.to_string())?)
                    .map_err(|_| "typing statistics response failed".to_owned())
            }
            StatisticsAction::Record { text, source, day } => {
                let recorded = store
                    .record(&text, source, &day)
                    .map_err(|error| error.to_string())?;
                Ok(json!({"recorded": recorded}))
            }
            StatisticsAction::SetEnabled { enabled } => serde_json::to_value(
                store
                    .set_enabled(enabled)
                    .map_err(|error| error.to_string())?,
            )
            .map_err(|_| "typing statistics response failed".to_owned()),
            StatisticsAction::Reset => {
                serde_json::to_value(store.reset().map_err(|error| error.to_string())?)
                    .map_err(|_| "typing statistics response failed".to_owned())
            }
        }
    })
}

/// Scan a skin root so native presenters read the same catalog the settings
/// page edits. Unreadable roots return an empty catalog, not an error; a
/// package that fails validation is reported as an issue and never rendered.
/// # Safety
/// `directory` points to `length` readable UTF-8 bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_skin_catalog(
    directory: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if directory.is_null() || length > 16384 {
            return Err("invalid skin directory buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(directory, length) };
        let directory =
            std::str::from_utf8(bytes).map_err(|_| "invalid skin directory encoding")?;
        if !std::path::Path::new(directory).is_absolute() {
            return Err("skin directory must be absolute".into());
        }
        serde_json::to_value(msime_client_core::skin::catalog::scan(directory))
            .map_err(|e| e.to_string())
    })
}

#[derive(Debug, Deserialize)]
struct SkinResourceRequest {
    directory: String,
    id: String,
    relative: String,
    kind: String,
}

#[derive(Debug, Deserialize)]
struct SkinStylesheetRequest {
    directory: String,
    id: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SkinResourceResponse {
    content_type: &'static str,
    bytes: Vec<u8>,
}

/// Read one validated image or font from an external skin package.
///
/// The request keeps the root directory explicit because Harmony's settings
/// bridge and the input-method ability share the same C ABI but have different
/// lifetimes. The package manifest is revalidated by `read_resource` on every
/// call, so a stale catalog cannot turn this endpoint into an arbitrary file
/// reader. `kind` is deliberately checked here as well: a WebView image reader
/// must never receive CSS or a font by mistake.
/// # Safety
/// `request` points to `length` readable UTF-8 JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_skin_resource(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length == 0 || length > 65_536 {
            return Err("invalid skin resource request".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let request: SkinResourceRequest =
            serde_json::from_slice(bytes).map_err(|_| "invalid skin resource request")?;
        if request.kind != "image" && request.kind != "font" {
            return Err("unsupported skin resource kind".into());
        }
        if !Path::new(&request.directory).is_absolute() {
            return Err("skin directory must be absolute".into());
        }
        let resource = msime_client_core::skin::catalog::read_resource(
            &request.directory,
            &request.id,
            &request.relative,
        )
        .map_err(|_| "skin resource unavailable")?;
        let expected = if request.kind == "image" {
            "image/"
        } else {
            "font/"
        };
        if !resource.content_type.starts_with(expected) {
            return Err("skin resource type mismatch".into());
        }
        serde_json::to_value(SkinResourceResponse {
            content_type: resource.content_type,
            bytes: resource.bytes,
        })
        .map_err(|_| "skin resource response failed".into())
    })
}

/// Read the stylesheet declared by an external skin package.
/// # Safety
/// `request` points to `length` readable UTF-8 JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_skin_toolbar_stylesheet(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length == 0 || length > 65_536 {
            return Err("invalid skin stylesheet request".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let request: SkinStylesheetRequest =
            serde_json::from_slice(bytes).map_err(|_| "invalid skin stylesheet request")?;
        if !Path::new(&request.directory).is_absolute() {
            return Err("skin directory must be absolute".into());
        }
        let stylesheet = msime_client_core::skin::catalog::read_toolbar_stylesheet(
            &request.directory,
            &request.id,
        )
        .map_err(|_| "skin stylesheet unavailable")?;
        serde_json::to_value(stylesheet).map_err(|_| "skin stylesheet response failed".into())
    })
}

/// Read saved clipboard history without observing or modifying the system clipboard.
/// # Safety
/// `directory` points to `length` readable UTF-8 bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_load_clipboard_history(
    directory: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if directory.is_null() || length > 16384 {
            return Err("invalid history directory buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(directory, length) };
        let directory =
            std::str::from_utf8(bytes).map_err(|_| "invalid history directory encoding")?;
        let path = std::path::Path::new(directory);
        if !path.is_absolute() {
            return Err("history directory must be absolute".into());
        }
        let enabled = PreferencesStore::new(path)
            .load()
            .map_err(|_| "history preferences unavailable")?
            .preferences
            .clipboard_history;
        if !enabled {
            return Ok(serde_json::json!({"enabled": false, "entries": []}));
        }
        let mut history = msime_client_core::clipboard::ClipboardHistoryStore::open(
            path.join("clipboard_history.json"),
        );
        history
            .load()
            .map_err(|_| "clipboard history unavailable")?;
        let entries: Vec<_> = history
            .entries()
            .iter()
            .map(|entry| entry.text.as_str())
            .collect();
        // Keep the existing ABI shape until native hosts opt into the
        // structured history bridge in their platform-specific migrations.
        Ok(serde_json::json!({"enabled": true, "entries": entries}))
    })
}

const MAX_MOBILE_CLIPBOARD_REQUEST_BYTES: usize = 524_288;
const MAX_APPLE_LEGACY_CLIPBOARD_BYTES: u64 = 4_000_000;
const APPLE_REFERENCE_DATE_UNIX_SECONDS: f64 = 978_307_200.0;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct MobileClipboardRequest {
    directory: String,
    action: MobileClipboardAction,
}

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum MobileClipboardAction {
    Load,
    Capture { text: String },
    SetPinned { text: String, pinned: bool },
    Remove { text: String },
    Clear,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct AppleLegacyClipboardEntry {
    id: String,
    text: String,
    date: f64,
    pinned: bool,
}

fn valid_uuid_string(value: &str) -> bool {
    value.len() == 36
        && value.bytes().enumerate().all(|(index, byte)| {
            if matches!(index, 8 | 13 | 18 | 23) {
                byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
}

fn apple_date_to_unix_ms(value: f64) -> Option<u64> {
    let milliseconds = (value + APPLE_REFERENCE_DATE_UNIX_SECONDS) * 1000.0;
    (milliseconds.is_finite() && milliseconds >= 0.0 && milliseconds <= u64::MAX as f64)
        .then(|| milliseconds.round() as u64)
}

fn apple_clipboard_migration_lock(root: &std::path::Path) -> Result<std::fs::File, String> {
    std::fs::create_dir_all(root).map_err(|_| "clipboard migration unavailable")?;
    let lock_path = root.join(".msime-clipboard-history-migration.lock");
    let mut options = std::fs::OpenOptions::new();
    options.create(true).truncate(false).read(true).write(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let lock = options
        .open(lock_path)
        .map_err(|_| "clipboard migration unavailable")?;
    lock.lock().map_err(|_| "clipboard migration unavailable")?;
    Ok(lock)
}

/// Migrate the fixed legacy Apple history into the shared mobile state once.
/// The source is removed only after the destination has been persisted.
pub fn migrate_apple_clipboard_history(root: &std::path::Path) -> Result<bool, String> {
    use std::io::Read;

    let _lock = apple_clipboard_migration_lock(root)?;

    let shared_path = root.join("MSIME").join("clipboard_history.json");
    let mut shared = msime_client_core::clipboard::ClipboardHistoryStore::open(&shared_path);
    shared
        .load()
        .map_err(|_| "shared clipboard history unavailable")?;
    if !shared.entries().is_empty() {
        return Ok(false);
    }

    let legacy_path = root.join("Clipboard").join("history.json");
    let metadata = match std::fs::symlink_metadata(&legacy_path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(false),
        Err(_) => return Err("legacy clipboard history unavailable".into()),
    };
    if !metadata.file_type().is_file() || metadata.len() > MAX_APPLE_LEGACY_CLIPBOARD_BYTES {
        return Err("invalid legacy clipboard history".into());
    }
    let mut bytes = Vec::new();
    std::fs::File::open(&legacy_path)
        .and_then(|file| {
            file.take(MAX_APPLE_LEGACY_CLIPBOARD_BYTES + 1)
                .read_to_end(&mut bytes)
        })
        .map_err(|_| "legacy clipboard history unavailable")?;
    if bytes.len() as u64 > MAX_APPLE_LEGACY_CLIPBOARD_BYTES {
        return Err("invalid legacy clipboard history".into());
    }
    let legacy: Vec<AppleLegacyClipboardEntry> =
        serde_json::from_slice(&bytes).map_err(|_| "invalid legacy clipboard history")?;
    if legacy.len() > 50 {
        return Err("invalid legacy clipboard history".into());
    }
    let mut ids = std::collections::HashSet::new();
    let mut texts = std::collections::HashSet::new();
    let mut entries = Vec::with_capacity(legacy.len());
    for entry in legacy {
        let Some(timestamp_ms) = apple_date_to_unix_ms(entry.date) else {
            return Err("invalid legacy clipboard history".into());
        };
        if !valid_uuid_string(&entry.id)
            || !ids.insert(entry.id)
            || !texts.insert(entry.text.clone())
            || !msime_client_core::clipboard::mobile_text_is_valid(&entry.text)
        {
            return Err("invalid legacy clipboard history".into());
        }
        entries.push(msime_client_core::clipboard::ClipboardHistoryEntry {
            text: entry.text,
            timestamp_ms,
            pinned: entry.pinned,
        });
    }
    let imported = shared
        .import_if_empty(entries)
        .map_err(|_| "clipboard migration failed")?;
    if imported {
        std::fs::remove_file(&legacy_path).map_err(|_| "clipboard migration cleanup failed")?;
    }
    Ok(imported)
}

/// Clear shared mobile history and its fixed Apple legacy source under one lock.
pub fn clear_mobile_clipboard_history(root: &std::path::Path) -> Result<(), String> {
    let _lock = apple_clipboard_migration_lock(root)?;
    let legacy_path = root.join("Clipboard").join("history.json");
    match std::fs::symlink_metadata(&legacy_path) {
        Ok(metadata) if metadata.file_type().is_file() => {
            std::fs::remove_file(&legacy_path).map_err(|_| "mobile clipboard clear failed")?;
        }
        Ok(_) => return Err("mobile clipboard clear failed".into()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => return Err("mobile clipboard clear failed".into()),
    }
    msime_client_core::clipboard::ClipboardHistoryStore::open(
        root.join("MSIME").join("clipboard_history.json"),
    )
    .clear()
    .map_err(|_| "mobile clipboard clear failed".to_owned())
}

/// Structured mobile clipboard history operations. The directory is the trusted
/// App Group root; shared data lives below MSIME and the fixed Apple legacy path
/// is migrated under a stable lock. This intentionally does not read or change
/// the desktop automatic-capture preference: mobile access is host-permission gated.
/// # Safety
/// `request` points to `length` readable JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_mobile_clipboard_history(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > MAX_MOBILE_CLIPBOARD_REQUEST_BYTES {
            return Err("invalid mobile clipboard request buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let request: MobileClipboardRequest = serde_json::from_slice(bytes)
            .map_err(|_| "invalid mobile clipboard request document")?;
        let root = std::path::Path::new(&request.directory);
        if !root.is_absolute() || request.directory.len() > 16384 {
            return Err("invalid mobile clipboard directory".into());
        }
        if matches!(&request.action, MobileClipboardAction::Clear) {
            clear_mobile_clipboard_history(root)?;
            return Ok(json!({"cleared": true, "migrated": false}));
        }
        let migrated = migrate_apple_clipboard_history(root)?;
        let path = root.join("MSIME").join("clipboard_history.json");
        let mut history = msime_client_core::clipboard::ClipboardHistoryStore::open(path);
        match request.action {
            MobileClipboardAction::Load => {
                history
                    .load()
                    .map_err(|_| "mobile clipboard history unavailable")?;
                Ok(json!({"entries": history.entries(), "migrated": migrated}))
            }
            MobileClipboardAction::Capture { text } => {
                if !msime_client_core::clipboard::mobile_text_is_valid(&text) {
                    return Ok(
                        json!({"captured": false, "reason": "invalid", "migrated": migrated}),
                    );
                }
                let captured = history
                    .push_mobile(text)
                    .map_err(|_| "mobile clipboard capture failed")?;
                Ok(json!({
                    "captured": captured,
                    "reason": (!captured).then_some("full"),
                    "migrated": migrated
                }))
            }
            MobileClipboardAction::SetPinned { text, pinned } => {
                if text.is_empty()
                    || text.len() > msime_client_core::clipboard::MAX_MOBILE_TEXT_BYTES
                {
                    return Err("invalid mobile clipboard entry".into());
                }
                let updated = history
                    .set_pinned(&text, pinned)
                    .map_err(|_| "mobile clipboard pin update failed")?;
                Ok(json!({"updated": updated, "migrated": migrated}))
            }
            MobileClipboardAction::Remove { text } => {
                if text.is_empty()
                    || text.len() > msime_client_core::clipboard::MAX_MOBILE_TEXT_BYTES
                {
                    return Err("invalid mobile clipboard entry".into());
                }
                let removed = history
                    .remove(&text)
                    .map_err(|_| "mobile clipboard removal failed")?;
                Ok(json!({"removed": removed, "migrated": migrated}))
            }
            MobileClipboardAction::Clear => unreachable!("clear handled before migration"),
        }
    })
}

/// Save host-sampled text only while shared history is enabled.
/// # Safety
/// `request` points to `length` readable JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_capture_clipboard_history(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 131072 {
            return Err("invalid history capture buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Capture {
            directory: String,
            text: String,
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let capture: Capture =
            serde_json::from_slice(bytes).map_err(|_| "invalid history capture document")?;
        if !std::path::Path::new(&capture.directory).is_absolute()
            || capture.directory.len() > 16384
            || capture.text.len() > msime_client_core::clipboard::MAX_TEXT_BYTES
        {
            return Err("invalid history capture parameters".into());
        }
        let captured = PreferencesStore::new(&capture.directory)
            .capture_clipboard_text(capture.text)
            .map_err(|_| "clipboard history capture failed")?;
        Ok(json!({"captured": captured}))
    })
}

/// Remove one saved history entry by exact content, without touching the clipboard.
/// # Safety
/// `request` points to `length` readable JSON bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_remove_clipboard_history(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 131072 {
            return Err("invalid history removal buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Removal {
            directory: String,
            text: String,
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let removal: Removal =
            serde_json::from_slice(bytes).map_err(|_| "invalid history removal document")?;
        let path = std::path::Path::new(&removal.directory);
        if !path.is_absolute() || removal.directory.len() > 16384 {
            return Err("invalid history directory".into());
        }
        if removal.text.is_empty()
            || removal.text.len() > msime_client_core::clipboard::MAX_TEXT_BYTES
        {
            return Err("invalid history entry".into());
        }
        if !PreferencesStore::new(path)
            .load()
            .map_err(|_| "history preferences unavailable")?
            .preferences
            .clipboard_history
        {
            return Err("clipboard history disabled".into());
        }
        let mut history = msime_client_core::clipboard::ClipboardHistoryStore::open(
            path.join("clipboard_history.json"),
        );
        let removed = history
            .remove(&removal.text)
            .map_err(|_| "clipboard history removal failed")?;
        Ok(json!({"removed": removed}))
    })
}

/// Try to read preferences without waiting for the writer lock.
/// # Safety
/// `directory` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_try_load_preferences(
    directory: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if directory.is_null() || length > 16384 {
            return Err("invalid preferences directory buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract.
        let bytes = unsafe { std::slice::from_raw_parts(directory, length) };
        let directory =
            std::str::from_utf8(bytes).map_err(|_| "invalid preferences directory encoding")?;
        if !std::path::Path::new(directory).is_absolute() {
            return Err("preferences directory must be absolute".into());
        }
        let snapshot = PreferencesStore::new(directory)
            .try_load()
            .map_err(|e| e.to_string())?;
        serde_json::to_value(snapshot).map_err(|e| e.to_string())
    })
}

/// Compare-and-swap save for a validated PreferencesSnapshot.
/// A successful save with clipboard history disabled clears the default history
/// under the shared preference/history locks, matching the desktop settings path.
///
/// # Safety
/// The caller must provide non-null pointers to readable UTF-8 buffers whose
/// lengths match the supplied lengths and remain valid for the duration of the call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_save_preferences(
    directory: *const u8,
    directory_length: usize,
    expected_revision: u64,
    snapshot: *const u8,
    snapshot_length: usize,
) -> *mut c_char {
    response(|| {
        if directory.is_null()
            || snapshot.is_null()
            || directory_length > 16384
            || snapshot_length > 16384
        {
            return Err("invalid preferences save buffer".into());
        }
        let directory_bytes = unsafe { std::slice::from_raw_parts(directory, directory_length) };
        let directory = std::str::from_utf8(directory_bytes)
            .map_err(|_| "invalid preferences directory encoding")?;
        if !std::path::Path::new(directory).is_absolute() {
            return Err("preferences directory must be absolute".into());
        }
        let snapshot_bytes = unsafe { std::slice::from_raw_parts(snapshot, snapshot_length) };
        let snapshot: PreferencesSnapshot =
            serde_json::from_slice(snapshot_bytes).map_err(|_| "invalid preferences snapshot")?;
        if snapshot.format_version != 1 {
            return Err("unsupported preferences format".into());
        }
        let store = PreferencesStore::new(directory);
        let saved = store
            .save(expected_revision, snapshot.preferences)
            .map_err(|e| e.to_string())?;
        if !saved.preferences.clipboard_history {
            store
                .clear_disabled_clipboard_history()
                .map_err(|e| e.to_string())?;
        }
        serde_json::to_value(saved).map_err(|e| e.to_string())
    })
}

/// The file name the reranking model is published under inside the resource set.
const SENTENCE_MODEL_FILE: &str = "sentence-model.safetensors";

/// The candidate reranking model, loaded once per path and shared by every session using it.
///
/// The path is separate from the dictionaries because the two artifacts change on entirely
/// different schedules. A resource set is identified by a hash over all of its artifacts, so adding
/// a seven megabyte model to the dictionary lock would make every model revision re-download the
/// hundred and eighty five megabytes of dictionaries alongside it. Hosts that have not adopted a
/// separate model artifact still find one placed next to the dictionaries.
///
/// Absence is the normal case for an installation that ships no model, so it is not an error and
/// leaves behaviour exactly as it was.
fn sentence_model(dictionaries: &str, configured: Option<&str>) -> Option<Arc<SentenceModel>> {
    static MODELS: OnceLock<Mutex<HashMap<PathBuf, Option<Arc<SentenceModel>>>>> = OnceLock::new();
    let path = match configured {
        Some(path) => PathBuf::from(path),
        None => Path::new(dictionaries).join(SENTENCE_MODEL_FILE),
    };
    let cache = MODELS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut cache = cache.lock().ok()?;
    // Keyed by path: two sessions may legitimately be pointed at different models, and a cache that
    // remembered only the first would silently serve one of them the other's weights.
    if let Some(cached) = cache.get(&path) {
        return cached.clone();
    }
    let loaded = std::fs::read(&path)
        .ok()
        .and_then(|bytes| match SentenceModel::load(&bytes) {
            Ok(model) => Some(Arc::new(model)),
            Err(error) => {
                // A corrupt or mismatched model is worth saying out loud: the input method keeps
                // working without it, so nothing else would ever reveal that it is not running.
                eprintln!("msime: ignoring {}: {error}", path.display());
                None
            }
        });
    cache.insert(path, loaded.clone());
    loaded
}

/// # Safety
/// `options` must point to `length` readable bytes for this call. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_create(options: *const u8, length: usize) -> *mut c_char {
    response(|| {
        if options.is_null() || length > 16384 {
            return Err("invalid options buffer".into());
        }
        // SAFETY: guaranteed by the C caller's documented buffer contract.
        let bytes = unsafe { std::slice::from_raw_parts(options, length) };
        let options: HostOptions =
            serde_json::from_slice(bytes).map_err(|_| "invalid options document")?;
        if options.api_version != 1 {
            return Err("unsupported host API version".into());
        }
        options.preferences.validate().map_err(|e| e.to_string())?;
        let page_size = options.preferences.candidate_page_size;
        let applied = options.preferences.clone();
        // Taken before the options are consumed, and kept separate from the engine's own paths.
        let sentence_model_path = options.sentence_model.clone();
        let options = options.into_engine_options();
        let dictionary_access = DictionaryAccess::try_session(
            std::path::Path::new(&options.user_data),
            std::path::Path::new(&options.dictionaries),
        )
        .map_err(|_| "dictionary access unavailable".to_owned())?
        .ok_or_else(|| "dictionary maintenance busy".to_owned())?;
        let mut engine = Session::new(&options).map_err(|e| e.to_string())?;
        let default_nine_key = matches!(applied.scheme, InputScheme::Quanpin)
            && matches!(applied.touch_keyboard_layout, TouchKeyboardLayout::NineKey);
        if default_nine_key {
            engine
                .set_nine_key_enabled(true)
                .map_err(|e| e.to_string())?;
        }
        // 默认输入状态 says which state a new focus session starts in, and the
        // host applies it as its own English passthrough - letters go straight
        // to the document, with no session involved. It is not the Engine's
        // dedicated English mode, which keeps a session and answers with
        // English word candidates. Seeding one from the other left a session
        // that could never reach Chinese: the host's toggle only flips
        // passthrough, so the "Chinese" half of it was English candidates, and
        // nothing on the way back clears a mode the user never turned on.
        // Dedicated English starts off and is only ever set by the menu row or
        // the hotkey that owns it.
        let mut runtime =
            Runtime::new_with_touch_layout(engine, page_size, applied.touch_keyboard_layout)
                .map_err(|e| e.to_string())?;
        runtime.set_reranker(
            sentence_model(&options.dictionaries, sentence_model_path.as_deref())
                .map(Reranker::new),
        );
        let view = runtime.view();
        let output = serde_json::to_value(&view).map_err(|e| e.to_string())?;
        SESSIONS.with(|sessions| {
            sessions.borrow_mut().insert(
                view.session,
                HostSession {
                    runtime,
                    options,
                    applied,
                    requested: None,
                    punctuation_override: None,
                    paired_punctuation_override: None,
                    punctuation_lock_override: None,
                    english_mode: false,
                    page_size_override: None,
                    nine_key_override: None,
                    voice: VoiceSessionState::default(),
                    _dictionary_access: dictionary_access,
                },
            )
        });
        Ok(output)
    })
}

#[no_mangle]
pub extern "C" fn msime_client_focus(handle: u64, focused: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            let result = session.runtime.focus(focused).map_err(|e| e.to_string())?;
            let result = session.complete_transition(result);
            serde_json::to_value(result).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_reset_cache(handle: u64) -> *mut c_char {
    dispatch(handle, Action::ResetCache)
}

#[no_mangle]
pub extern "C" fn msime_client_voice_start(handle: u64) -> *mut c_char {
    response(|| with_session(handle, |session| Ok(json!(session.voice.start()))))
}

#[no_mangle]
pub extern "C" fn msime_client_voice_cancel(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session.voice.cancel();
            Ok(Value::Null)
        })
    })
}

/// Capture a bounded PCM16-compatible sample buffer through the Engine audio
/// layer. The returned JSON contains only the samples for this call; callers
/// must transport them immediately and must not log or persist them.
#[no_mangle]
pub extern "C" fn msime_client_voice_capture(milliseconds: u32) -> *mut c_char {
    response(|| {
        if !(1..=60_000).contains(&milliseconds) {
            return Err("invalid voice capture duration".into());
        }
        let samples = msime_engine_bridge::capture_audio(milliseconds);
        if samples.is_empty() {
            return Err("voice capture unavailable".into());
        }
        Ok(json!({ "sample_rate": 16000, "channels": 1, "samples": samples }))
    })
}

/// Apply asynchronous ASR text only for the active voice token.
///
/// # Safety
/// `text` must point to a readable UTF-8 buffer of `length` bytes and must not
/// be null. The buffer is not retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_apply(
    handle: u64,
    generation: u64,
    text: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if text.is_null() || length > 65536 {
            return Err("invalid voice text buffer".into());
        }
        let text = std::str::from_utf8(unsafe { std::slice::from_raw_parts(text, length) })
            .map_err(|_| "voice text is not UTF-8")?;
        with_session(handle, |session| {
            Ok(session
                .voice
                .apply(generation, text)
                .map(Value::String)
                .unwrap_or(Value::Null))
        })
    })
}

/// Plan eligible visible candidates using shared script filters. No I/O.
/// # Safety
/// `request` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_custom_translation_plan(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid translation plan buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Candidate {
            text: String,
            source: u8,
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request {
            target_language: String,
            candidates: Vec<Candidate>,
        }
        let request: Request =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, length) })
                .map_err(|_| "invalid translation plan")?;
        if request.candidates.len() > 9
            || !["en", "fr", "ja", "es", "ru", "de", "ko"]
                .contains(&request.target_language.as_str())
        {
            return Err("invalid translation plan parameters".into());
        }
        let mut results = Vec::new();
        for candidate in request.candidates {
            // Engine CandidateSource::Emoji / Kaomoji, and unknown sources.
            if matches!(candidate.source, 6 | 7 | 10..=255) || candidate.text.chars().count() > 40 {
                continue;
            }
            let (source, target, key) =
                if msime_client_core::translation::is_cloud_translatable_english(&candidate.text) {
                    ("en", "zh", candidate.text.to_ascii_lowercase())
                } else if msime_client_core::translation::is_cloud_translatable_chinese(
                    &candidate.text,
                ) {
                    (
                        "zh",
                        request.target_language.as_str(),
                        candidate.text.clone(),
                    )
                } else {
                    continue;
                };
            let item = json!({"text":candidate.text,"key":key,"source_language":source,"target_language":target});
            if !results.contains(&item) {
                results.push(item);
            }
        }
        Ok(json!(results))
    })
}

/// Build a pure AI HTTP descriptor containing credentials. Never log it.
/// # Safety
/// `request` references `length` readable JSON bytes. No buffers are retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_ai_http_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid AI request buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request {
            config: msime_client_core::preferences::AiAssistantPreferences,
            input: msime_client_core::ai::AiSuggestionRequest,
        }
        let request: Request =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, length) })
                .map_err(|_| "invalid AI request document")?;
        msime_client_core::ai::chat_completion_http_request(&request.config, &request.input)
            .map(|value| value.unwrap_or(Value::Null))
            .map_err(|e| e.to_string())
    })
}
/// Parse a successful AI HTTP response into a bounded string array, or null.
/// # Safety
/// `body` references `length` readable bytes. No buffers are retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_parse_ai_response(
    body: *const u8,
    length: usize,
    limit: u8,
) -> *mut c_char {
    response(|| {
        if body.is_null() || length > 1048576 || !(1..=10).contains(&limit) {
            return Err("invalid AI response buffer".into());
        }
        Ok(msime_client_core::ai::parse_chat_completion_response(
            unsafe { std::slice::from_raw_parts(body, length) },
            limit,
        )
        .map(|response| {
            json!(response
                .candidates
                .into_iter()
                .map(|candidate| candidate.text)
                .collect::<Vec<_>>())
        })
        .unwrap_or(Value::Null))
    })
}

/// Read/write private learned glosses on a host-owned IO worker. Never log inputs.
/// # Safety
/// `request` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_learned_translation_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid learned translation buffer".into());
        }
        learned_translation::execute(unsafe { std::slice::from_raw_parts(request, length) })
            .map_err(str::to_owned)
    })
}

/// Build a signed Tencent TMT descriptor with an exact UTF-8 payload. No I/O.
/// # Safety
/// `request` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_tencent_translation_http_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid Tencent request buffer".into());
        }
        tencent_translation::descriptor(unsafe { std::slice::from_raw_parts(request, length) })
            .map_err(String::from)
    })
}

/// Build a NiuTrans v2 form descriptor. No network or credential persistence.
/// # Safety
/// `request` must reference `length` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn msime_client_niutrans_translation_http_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid NiuTrans request buffer".into());
        }
        niutrans_translation::descriptor(unsafe { std::slice::from_raw_parts(request, length) })
            .map_err(String::from)
    })
}

/// Parse a bounded response preserving batch positions (unusable slots are null).
/// # Safety
/// `body` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_parse_tencent_translation_response(
    body: *const u8,
    length: usize,
    expected: usize,
) -> *mut c_char {
    response(|| {
        if body.is_null() || length > 1048576 || !(1..=9).contains(&expected) {
            return Err("invalid Tencent response buffer".into());
        }
        Ok(tencent_translation::parse(
            unsafe { std::slice::from_raw_parts(body, length) },
            expected,
        )
        .unwrap_or(Value::Null))
    })
}

/// Parse one bounded NiuTrans response into a formatted gloss, or null.
/// # Safety
/// `body` must reference `length` readable bytes.
#[no_mangle]
pub unsafe extern "C" fn msime_client_parse_niutrans_translation_response(
    body: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if body.is_null() || length > 1048576 {
            return Err("invalid NiuTrans response buffer".into());
        }
        Ok(
            niutrans_translation::parse(unsafe { std::slice::from_raw_parts(body, length) })
                .unwrap_or(Value::Null),
        )
    })
}

/// Build a DeepLX-compatible request for a host-owned HTTP transport. No I/O.
/// # Safety
/// `request` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_custom_translation_http_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 16384 {
            return Err("invalid custom translation request buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Request {
            config: msime_input_runtime::TranslationProviderConfig,
            text: String,
            source_language: String,
            target_language: String,
        }
        let Request {
            mut config,
            text,
            source_language,
            target_language,
        }: Request = serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, length) })
            .map_err(|_| "invalid custom translation request")?;
        // Match the Windows source: settings pasted from a password manager
        // are trimmed before endpoint and credential validation.
        config.endpoint = config.endpoint.trim().to_owned();
        config.api_key = config.api_key.trim().to_owned();
        if !config.enabled {
            return Ok(Value::Null);
        }
        let valid_language = |value: &str| {
            !value.is_empty()
                && value.len() <= 16
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_alphabetic() || byte == b'-')
        };
        if !msime_client_core::translation::is_supported_endpoint(&config.endpoint)
            || config.api_key.len() > 4096
            || config.api_key.chars().any(char::is_control)
            || text.is_empty()
            || text.chars().count() > 40
            || text.chars().any(char::is_control)
            || !valid_language(&source_language)
            || !valid_language(&target_language)
        {
            return Err("invalid custom translation parameters".into());
        }
        let mut headers = json!({"Content-Type": "application/json"});
        if !config.api_key.is_empty() {
            headers["Authorization"] = Value::String(format!("Bearer {}", config.api_key));
        }
        Ok(json!({
            "url": config.endpoint,
            "method": "POST",
            "headers": headers,
            "body": {"text": text, "source_lang": source_language.to_ascii_uppercase(),
                "target_lang": target_language.to_ascii_uppercase()},
            "timeout_ms": 2500,
            "max_response_bytes": 1048576,
        }))
    })
}

/// Parse a bounded provider document; malformed/no-result documents return null.
/// # Safety
/// `body` must reference `length` readable bytes for this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_parse_custom_translation_response(
    body: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if body.is_null() || length > 1048576 {
            return Err("invalid custom translation response buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(body, length) };
        let result = std::str::from_utf8(bytes)
            .ok()
            .and_then(msime_client_core::translation::parse_translation_response)
            .and_then(|text| msime_client_core::translation::format_translation_gloss(&text))
            .filter(|text| !text.is_empty() && text.len() <= 4096);
        Ok(result.map(Value::String).unwrap_or(Value::Null))
    })
}

/// Apply asynchronous candidate translations for an exact candidate generation.
/// The buffer is a JSON array of `{text, translation}` objects and is not retained.
///
/// # Safety
/// `translations` must point to a readable UTF-8 buffer of `length` bytes and
/// must not be null. The buffer is not retained after this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_apply_translations(
    handle: u64,
    generation: u64,
    translations: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if translations.is_null() || length > 1_048_576 {
            return Err("invalid translation buffer".into());
        }
        #[derive(Deserialize)]
        #[serde(deny_unknown_fields)]
        struct Translation {
            text: String,
            translation: String,
        }
        let bytes = unsafe { std::slice::from_raw_parts(translations, length) };
        let values: Vec<Translation> =
            serde_json::from_slice(bytes).map_err(|_| "translations must be a UTF-8 JSON array")?;
        if values.len() > 4096
            || values.iter().any(|item| {
                item.text.len() > 4096
                    || item.translation.len() > 4096
                    || item.text.chars().any(char::is_control)
                    || item.translation.chars().any(char::is_control)
            })
        {
            return Err("translation entries exceed limits".into());
        }
        with_session(handle, |session| {
            let applied = session.runtime.apply_translations(
                generation,
                values.into_iter().map(|item| (item.text, item.translation)),
            );
            Ok(json!({"applied": applied, "view": session.runtime.view()}))
        })
    })
}

/// Save short English-target glosses through Engine into a user-owned overlay.
/// # Safety
/// Both pointers must reference readable buffers of their declared lengths.
#[no_mangle]
pub unsafe extern "C" fn msime_client_translation_gloss_save(
    request: *const u8,
    request_length: usize,
    user_data: *const u8,
    user_data_length: usize,
) -> *mut c_char {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Request {
        target_language: String,
        translations: Vec<msime_input_runtime::TranslationResult>,
    }
    response(|| {
        if request.is_null()
            || user_data.is_null()
            || request_length > 131_072
            || user_data_length > 4096
        {
            return Err("invalid translation persistence buffer".into());
        }
        let request: Request =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, request_length) })
                .map_err(|_| "invalid translation persistence request")?;
        let user_data =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(user_data, user_data_length) })
                .map_err(|_| "invalid user data path")?;
        if !std::path::Path::new(user_data).is_absolute()
            || !std::path::Path::new(user_data).is_dir()
        {
            return Err("user data requires an existing absolute directory".into());
        }
        if request.translations.len() > 9
            || request.translations.iter().any(|item| {
                item.text.len() > 4096
                    || item.translation.len() > 4096
                    || item.text.chars().any(char::is_control)
            })
        {
            return Err("translation persistence entries exceed limits".into());
        }
        let mut saved = 0;
        if request.target_language == "en" {
            use msime_client_core::translation::{
                format_translation_gloss, is_cloud_translatable_chinese,
                is_cloud_translatable_english, should_persist_translation,
            };
            for item in request.translations {
                let english = is_cloud_translatable_english(&item.text);
                if item.text.chars().count() > 40
                    || (!english && !is_cloud_translatable_chinese(&item.text))
                {
                    continue;
                }
                let Some(gloss) = format_translation_gloss(&item.translation) else {
                    continue;
                };
                if !should_persist_translation(&item.text, &gloss) {
                    continue;
                }
                let key = if english {
                    item.text.to_ascii_lowercase()
                } else {
                    item.text
                };
                if msime_engine_bridge::save_candidate_gloss(user_data, !english, &key, &gloss) {
                    saved += 1;
                }
            }
        }
        Ok(json!({"saved":saved}))
    })
}

/// Resolve copied candidates against the packaged offline English dictionary.
/// This owns no session state and is safe to call on a host worker thread. The
/// copied generation is echoed so the host can apply only to the originating view.
///
/// # Safety
/// Both pointers must reference readable buffers for their stated lengths and
/// remain valid for this call. The buffers are not retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_candidate_gloss_request(
    request: *const u8,
    request_length: usize,
    resources: *const u8,
    resources_length: usize,
) -> *mut c_char {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Request {
        generation: u64,
        #[serde(default)]
        user_data: Option<String>,
        candidates: Vec<GlossCandidate>,
    }
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct GlossCandidate {
        text: String,
        source: u8,
    }
    response(|| {
        if request.is_null()
            || resources.is_null()
            || request_length > 262_144
            || resources_length > 4096
        {
            return Err("invalid candidate gloss buffer".into());
        }
        let request: Request =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, request_length) })
                .map_err(|_| "invalid candidate gloss request")?;
        if request.candidates.len() > 4096
            || request.candidates.iter().any(|candidate| {
                candidate.text.is_empty()
                    || candidate.text.len() > 4096
                    || candidate.text.chars().any(char::is_control)
            })
        {
            return Err("candidate gloss entries exceed limits".into());
        }
        let resources =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(resources, resources_length) })
                .map_err(|_| "resources path is not UTF-8")?;
        if !std::path::Path::new(resources).is_absolute() {
            return Err("resources path must be absolute".into());
        }
        let candidates = request
            .candidates
            .iter()
            .map(|candidate| (candidate.text.clone(), candidate.source))
            .collect::<Vec<_>>();
        let user_data = request.user_data.as_deref().unwrap_or("");
        if !user_data.is_empty()
            && (user_data.len() > 4096 || !std::path::Path::new(user_data).is_absolute())
        {
            return Err("user data path must be absolute".into());
        }
        let glosses =
            msime_engine_bridge::candidate_glosses_with_user(resources, user_data, &candidates)
                .map_err(|_| "candidate gloss dictionary unavailable")?;
        if glosses.len() != candidates.len() {
            return Err("candidate gloss response mismatch".into());
        }
        candidates
            .iter()
            .zip(&glosses)
            .try_fold(0_usize, |total, ((text, _), gloss)| {
                if gloss.len() > 4096 {
                    return None;
                }
                total.checked_add(text.len())?.checked_add(gloss.len())
            })
            .filter(|total| *total <= 900_000)
            .ok_or("candidate gloss response exceeds limits")?;
        let translations = candidates
            .into_iter()
            .zip(glosses)
            .filter_map(|((text, _), translation)| {
                (!translation.is_empty()).then_some(json!({
                    "text": text,
                    "translation": translation,
                }))
            })
            .collect::<Vec<_>>();
        Ok(json!({
            "generation": request.generation,
            "translations": translations,
        }))
    })
}

/// Query copied prefixes against the packaged English dictionary. This does not
/// create or mutate an Engine session and is suitable for a host worker thread.
///
/// # Safety
/// The request and resources pointers must point to readable buffers of the supplied lengths.
/// Neither buffer is retained after the call returns.
#[no_mangle]
pub unsafe extern "C" fn msime_client_english_completions_request(
    request: *const u8,
    request_length: usize,
    resources: *const u8,
    resources_length: usize,
) -> *mut c_char {
    #[derive(Deserialize)]
    #[serde(deny_unknown_fields)]
    struct Request {
        prefix: String,
        limit: u8,
    }
    response(|| {
        if request.is_null()
            || resources.is_null()
            || request_length > 16_384
            || resources_length > 4_096
        {
            return Err("invalid English completion buffer".into());
        }
        let request: Request =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, request_length) })
                .map_err(|_| "invalid English completion request")?;
        if !(1..=32).contains(&request.limit)
            || request.prefix.is_empty()
            || request.prefix.len() > 128
            || !request
                .prefix
                .bytes()
                .all(|byte| byte.is_ascii_alphabetic())
        {
            return Err("invalid English completion prefix".into());
        }
        let resources =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(resources, resources_length) })
                .map_err(|_| "resources path is not UTF-8")?;
        if !Path::new(resources).is_absolute() {
            return Err("resources path must be absolute".into());
        }
        let items = msime_engine_bridge::english_completions(
            resources,
            &request.prefix,
            usize::from(request.limit),
        )
        .map_err(|_| "English completion dictionary unavailable")?;
        Ok(json!({"prefix": request.prefix, "items": items}))
    })
}

/// Native presentation override; changes wait for the current composition to end.
#[no_mangle]
pub extern "C" fn msime_client_set_candidate_page_size(handle: u64, size: u8) -> *mut c_char {
    response(|| {
        if !(1..=9).contains(&size) {
            return Err("candidate page size must be between 1 and 9".into());
        }
        with_session(handle, |session| {
            if session.runtime.is_idle() {
                session
                    .runtime
                    .set_page_size(size)
                    .map_err(|e| e.to_string())?;
            }
            session.page_size_override = Some(size);
            let view = session.runtime.view();
            Ok(json!({"deferred": view.page_size != usize::from(size), "view": view}))
        })
    })
}

/// Override the live host punctuation mode without persisting preferences.
#[no_mangle]
pub extern "C" fn msime_client_set_chinese_punctuation(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_chinese_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.punctuation_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_paired_punctuation(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_paired_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.paired_punctuation_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_punctuation_lock(handle: u64, lock: u8) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_punctuation_lock(lock)
                .map_err(|e| e.to_string())?;
            session.punctuation_lock_override = Some(lock);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_english_mode(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_dedicated_english(enabled)
                .map_err(|e| e.to_string())?;
            session.english_mode = enabled;
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

/// Enable Engine-owned quanpin nine-key digit handling after composition is idle.
#[no_mangle]
pub extern "C" fn msime_client_set_nine_key_mode(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_nine_key_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.nine_key_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_character_width(handle: u64, fullwidth: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session.runtime.set_character_width(if fullwidth {
                CharacterWidth::Fullwidth
            } else {
                CharacterWidth::Halfwidth
            });
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_character(handle: u64, ascii: u8, shift: bool) -> *mut c_char {
    dispatch(
        handle,
        Action::Character {
            value: ascii,
            shift,
        },
    )
}

#[no_mangle]
pub extern "C" fn msime_client_command(handle: u64, command: u32) -> *mut c_char {
    let action = match command {
        0 => Action::Command(Command::Backspace),
        1 => Action::SelectHighlighted,
        2 => Action::Command(Command::CommitRaw),
        3 => Action::Command(Command::Cancel),
        4 => Action::Command(Command::MoveLeft),
        5 => Action::Command(Command::MoveRight),
        6 => Action::Command(Command::MoveHome),
        7 => Action::Command(Command::MoveEnd),
        8 => Action::Command(Command::DeleteForward),
        9 => Action::Finish,
        10 => Action::Command(Command::CycleKanaVariant),
        11 => Action::Command(Command::CommitReading),
        12 => Action::SegmentBackspace,
        13 => Action::SegmentMoveLeft,
        14 => Action::SegmentMoveRight,
        100 => Action::NextPage,
        101 => Action::PreviousPage,
        102 => Action::NextCandidate,
        103 => Action::PreviousCandidate,
        104 => Action::FirstCandidateOnPage,
        105 => Action::LastCandidateOnPage,
        _ => return response(|| Err("unknown input command".into())),
    };
    dispatch(handle, action)
}

/// Explicit native punctuation route, even when a local mode consumes characters.
#[no_mangle]
pub extern "C" fn msime_client_punctuation(handle: u64, ascii: u8) -> *mut c_char {
    dispatch(handle, Action::Punctuation(ascii))
}

/// Resolve punctuation using the platform editor's immediately preceding
/// Unicode scalar. Zero means that no preceding scalar is available. Only the
/// scalar value crosses the host boundary; document text is never retained.
#[no_mangle]
pub extern "C" fn msime_client_punctuation_with_context(
    handle: u64,
    ascii: u8,
    preceding: u32,
) -> *mut c_char {
    if !ascii.is_ascii_punctuation() {
        return response(|| Err("invalid punctuation".into()));
    }
    let preceding = if preceding == 0 {
        None
    } else {
        match char::from_u32(preceding) {
            Some(value) => Some(value),
            None => return response(|| Err("invalid preceding character".into())),
        }
    };
    let action = SESSIONS.with(|sessions| {
        let sessions = sessions
            .try_borrow()
            .map_err(|_| "reentrant host call".to_owned())?;
        let session = sessions
            .get(&handle)
            .ok_or_else(|| "unknown session or wrong thread".to_owned())?;
        let view = session.runtime.view();
        let lock = match session.punctuation_lock_override {
            Some(1) => msime_client_core::preferences::PunctuationLock::Chinese,
            Some(2) => msime_client_core::preferences::PunctuationLock::English,
            Some(_) => msime_client_core::preferences::PunctuationLock::Follow,
            None => session.applied.punctuation_lock,
        };
        let route = punctuation_route(PunctuationContext {
            character: ascii,
            preceding,
            host_context_available: !session.english_mode
                && !view.dedicated_english
                && view.local_mode == "none"
                && view.scheme != 3,
            has_composition: !session.runtime.is_idle(),
            chinese_punctuation: session
                .punctuation_override
                .unwrap_or(session.applied.chinese_punctuation),
            smart_punctuation: session.applied.smart_punctuation,
            lock,
        });
        Ok(match route {
            PunctuationRoute::Engine => Action::Punctuation(ascii),
            PunctuationRoute::Ascii => Action::PunctuationAscii(ascii),
        })
    });
    match action {
        Ok(action) => dispatch(handle, action),
        Err(error) => response(|| Err(error)),
    }
}

/// Notify Engine that a host-emitted paired closing mark completed the opening.
#[no_mangle]
pub extern "C" fn msime_client_balance_paired_punctuation_after_auto_close(
    handle: u64,
    opening: u8,
) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .balance_paired_punctuation_after_auto_close(opening)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

/// Finish the highlighted composition and append a literal ASCII punctuation
/// mark. This is kept separate from Engine punctuation so a platform host can
/// apply its own surrounding-text policy without changing the shared table.
#[no_mangle]
pub extern "C" fn msime_client_punctuation_ascii(handle: u64, ascii: u8) -> *mut c_char {
    dispatch(handle, Action::PunctuationAscii(ascii))
}

#[no_mangle]
pub extern "C" fn msime_client_select(handle: u64, generation: u64, index: usize) -> *mut c_char {
    dispatch(
        handle,
        Action::Select(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Select any candidate returned by `msime_client_all_candidates` for the exact
/// session generation. Regular `msime_client_select` remains page-bounded.
#[no_mangle]
pub extern "C" fn msime_client_select_any_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::SelectAnyCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_pin_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::PinCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_remove_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::RemoveCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_fix_candidate_position(
    handle: u64,
    generation: u64,
    index: usize,
    position: u8,
) -> *mut c_char {
    if !(1..=5).contains(&position) {
        return response(|| Err("candidate position must be between 1 and 5".into()));
    }
    dispatch(
        handle,
        Action::FixCandidatePosition(
            CandidateId {
                session: handle,
                generation,
                index,
            },
            position,
        ),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_clear_candidate_position(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::ClearCandidatePosition(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Select one spelling from View.nine_key_spellings for the exact view generation.
#[no_mangle]
pub extern "C" fn msime_client_choose_nine_key_spelling(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::ChooseNineKeySpelling(NineKeySpellingId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Copy every cached Engine candidate only when a host opens an expanded panel.
#[no_mangle]
pub extern "C" fn msime_client_all_candidates(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            serde_json::to_value(session.runtime.all_candidates()).map_err(|e| e.to_string())
        })
    })
}

/// Return bounded, lower-case English completions for the word immediately before the cursor.
/// This query is read-only and does not touch the Engine session's composition state.
///
/// # Safety
/// `prefix` must point to `prefix_length` readable UTF-8 bytes. The buffer is not retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_english_completions(
    handle: u64,
    prefix: *const u8,
    prefix_length: usize,
    limit: usize,
) -> *mut c_char {
    response(|| {
        if prefix.is_null() || !(1..=64).contains(&prefix_length) || !(1..=32).contains(&limit) {
            return Err("invalid English completion buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(prefix, prefix_length) };
        let prefix = std::str::from_utf8(bytes).map_err(|_| "invalid English completion prefix")?;
        if !prefix.bytes().all(|value| value.is_ascii_alphabetic()) {
            return Err("invalid English completion prefix".into());
        }
        with_session(handle, |session| {
            let words = msime_engine_bridge::english_completions(
                &session.options.dictionaries,
                prefix,
                limit,
            )
            .map_err(|error| error.to_string())?;
            Ok(json!({"completions": words}))
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_view(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_online_query(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            let Some(query) = session.runtime.online_query().map_err(|e| e.to_string())? else {
                return Ok(Value::Null);
            };
            let mut value = serde_json::to_value(query).map_err(|e| e.to_string())?;
            value["cloud_candidates"] = Value::Bool(session.cloud_candidates_enabled());
            value["ai_assistant"] =
                serde_json::to_value(session.ai_provider_config()).map_err(|e| e.to_string())?;
            Ok(value)
        })
    })
}

/// Build a validated AI HTTP descriptor for a copied OnlineQuery.
/// Credentials stay inside the host session; only the returned descriptor is
/// consumed by the platform transport worker and the query must still match
/// the current AI preferences.
/// # Safety
/// `query` references `query_length` readable UTF-8 JSON bytes. No buffers are retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_ai_request_for_query(
    handle: u64,
    query: *const u8,
    query_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || query_length > 16384 {
            return Err("invalid AI query buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        with_session(handle, |session| {
            if !query.ai_eligible || !session.ai_query_is_current(&query) {
                return Ok(Value::Null);
            }
            let preferences = session
                .requested
                .as_ref()
                .map(|snapshot| &snapshot.preferences)
                .unwrap_or(&session.applied);
            // The limit has to come from the same config the descriptor is
            // built from: chat_completion_http_request rejects a request whose
            // limit disagrees with its config, and the query document's copy
            // can lag the pending preferences this call is meant to follow.
            let config = &preferences.ai_assistant;
            let request = AiSuggestionRequest {
                segmented_pinyin: query.pinyin_segments,
                context: query.ai_context,
                candidate_limit: config.candidate_limit,
            };
            msime_client_core::ai::chat_completion_http_request(config, &request)
                .map(|value| value.unwrap_or(Value::Null))
                .map_err(|error| error.to_string())
        })
    })
}

/// Return the visible candidate texts that may receive asynchronous translations.
/// The generation must be echoed to `msime_client_apply_translations`.
#[no_mangle]
pub extern "C" fn msime_client_translation_query(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            // Provider settings can change while Engine preferences wait for
            // composition to finish. Query with the newest validated settings.
            let preferences = session
                .requested
                .as_ref()
                .map(|snapshot| &snapshot.preferences)
                .unwrap_or(&session.applied);
            // The offline English gloss rides this same query, so it has to be
            // reachable with online translation off: it is a packaged
            // dictionary lookup and never leaves the machine.
            let mut target_languages = vec![preferences.translation_target_language];
            if let Some(secondary) = preferences.translation_secondary_language {
                if !target_languages.contains(&secondary) {
                    target_languages.push(secondary);
                }
            }
            let english_gloss = preferences.candidate_english_gloss
                && target_languages.iter().any(|language| {
                    matches!(
                        language,
                        msime_client_core::preferences::TranslationTargetLanguage::En
                    )
                });
            let persist_english_translation = preferences.candidate_translations
                && matches!(
                    preferences.translation_target_language,
                    msime_client_core::preferences::TranslationTargetLanguage::En
                );
            if !preferences.candidate_translations && !english_gloss {
                return Ok(Value::Null);
            }
            let view = session.runtime.view();
            // Windows does not request glosses for Japanese candidates. Use
            // Engine's active mode, including temporary Japanese composition.
            if view.candidates.is_empty()
                || view.scheme == 3
                || view.local_mode == "temporary_japanese"
            {
                return Ok(Value::Null);
            }
            let candidates = view
                .candidates
                .iter()
                .map(|candidate| json!({ "text": candidate.text }))
                .collect::<Vec<_>>();
            let custom_translation = &preferences.custom_translation;
            let tencent = &preferences.tencent_tmt;
            // Selecting custom translation must never silently fall back to TMT.
            let tencent_tmt = (!custom_translation.enabled
                && !preferences.niutrans.enabled
                && tencent.enabled
                && msime_client_core::translation::usable_tencent_secret(&tencent.secret_id)
                && msime_client_core::translation::usable_tencent_secret(&tencent.secret_key))
            .then(|| serde_json::to_value(tencent))
            .transpose()
            .map_err(|_| "invalid Tencent translation configuration")?;
            let custom_translation = (custom_translation.enabled
                && !preferences.niutrans.enabled
                && !custom_translation.endpoint.is_empty())
            .then(|| {
                json!({
                    "enabled": true,
                    "endpoint": &custom_translation.endpoint,
                    "api_key": &custom_translation.api_key,
                })
            });
            let niutrans = (preferences.niutrans.enabled
                && msime_client_core::translation::usable_niutrans_credential(
                    &preferences.niutrans.app_id,
                )
                && msime_client_core::translation::usable_niutrans_credential(
                    &preferences.niutrans.apikey,
                ))
            .then(|| serde_json::to_value(&preferences.niutrans))
            .transpose()
            .map_err(|_| "invalid NiuTrans translation configuration")?;
            Ok(json!({
                "generation": view.generation,
                "target_language": serde_json::to_value(preferences.translation_target_language)
                    .map_err(|e| e.to_string())?,
                "target_languages": target_languages
                    .iter()
                    .map(|language| serde_json::to_value(language).map_err(|e| e.to_string()))
                    .collect::<Result<Vec<_>, _>>()?,
                "candidates": candidates,
                "custom_translation": custom_translation,
                "tencent_tmt": tencent_tmt,
                "niutrans": niutrans,
                "english_gloss": english_gloss,
                // The packaged resource path is only needed for offline
                // lookup. The user path is also needed by a background host
                // worker to persist successful English-target translations.
                "resources": english_gloss.then(|| session.options.resources.clone()),
                "user_data": (english_gloss || persist_english_translation)
                    .then(|| session.options.user_data.clone()),
            }))
        })
    })
}

/// Build the default HTTPS cloud URL for a copied eligible query. The host
/// performs the request and later calls `msime_client_apply_online_candidate`.
///
/// # Safety
/// `query` must point to a readable UTF-8 JSON buffer of `query_length` bytes,
/// or be null only when `query_length` is zero. The buffer is not retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_cloud_request_url(
    query: *const u8,
    query_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || query_length > 16384 {
            return Err("invalid cloud query buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let url = msime_input_runtime::cloud_request_url(&query)
            .ok_or_else(|| "cloud query is not eligible".to_owned())?;
        Ok(json!(url))
    })
}

/// Query a user-owned Unix-socket provider off the session thread.
/// Returns null when the provider has no candidate or is unavailable.
///
/// # Safety
/// The caller must provide readable buffers of the stated lengths, or null pointers only with
/// zero lengths; buffers are read for the duration of this call and never retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_online_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16384 || socket_length > 4096
        {
            return Err("invalid online provider buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .query_candidates(query)
            .map(|candidates| {
                let rows: Vec<_> = candidates
                    .into_iter()
                    .map(|(text, source)| json!({"text": text, "source": source}))
                    .collect();
                // Preserve the single-result fields for older CLI consumers.
                let mut value = rows.first().cloned().unwrap_or(json!({}));
                value["candidates"] = json!(rows);
                value
            })
            .unwrap_or(Value::Null))
    })
}

/// Forward one account-backed dictionary operation to a user-owned Linux
/// provider. The request is validated before it crosses the Unix socket.
///
/// # Safety
/// The caller must provide non-null readable buffers of the stated lengths. The buffers are read
/// only for the duration of this call and are never retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_cloud_dictionary_provider_request(
    request: *const u8,
    request_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null()
            || socket_path.is_null()
            || request_length > 65_536
            || socket_length > 4096
        {
            return Err("invalid cloud dictionary provider buffer".into());
        }
        let request_bytes = unsafe { std::slice::from_raw_parts(request, request_length) };
        let parsed =
            serde_json::from_slice::<cloud_dictionary::CloudDictionaryRequest>(request_bytes)
                .map_err(|_| "invalid cloud dictionary request")?;
        cloud_dictionary::validate_cloud_request(&parsed).map_err(|error| error.to_owned())?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        let request = serde_json::from_slice::<serde_json::Value>(request_bytes)
            .map_err(|_| "invalid cloud dictionary request")?;
        msime_input_runtime::UnixSocketProvider::new(path)
            .cloud_dictionary(request)
            .ok_or_else(|| "cloud dictionary provider unavailable".to_owned())
    })
}

/// Forward one validated account-backed cloud clipboard operation to a
/// user-owned Linux provider.
///
/// # Safety
/// The caller must provide non-null readable buffers of the stated lengths. The buffers are read
/// only for the duration of this call and are never retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_cloud_clipboard_provider_request(
    request: *const u8,
    request_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null()
            || socket_path.is_null()
            || request_length > 65_536
            || socket_length > 4096
        {
            return Err("invalid cloud clipboard provider buffer".into());
        }
        let request_bytes = unsafe { std::slice::from_raw_parts(request, request_length) };
        let request = serde_json::from_slice::<serde_json::Value>(request_bytes)
            .map_err(|_| "invalid cloud clipboard request")?;
        cloud_clipboard::validate_request(&request).map_err(|error| error.to_owned())?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        msime_input_runtime::UnixSocketProvider::new(path)
            .cloud_clipboard(request)
            .ok_or_else(|| "cloud clipboard provider unavailable".to_owned())
    })
}

/// Query a user-owned Unix-socket translation provider.
///
/// # Safety
/// Both buffers must be non-null readable UTF-8 buffers for the stated lengths;
/// they are copied for the duration of this call and never retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_translation_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16384 || socket_length > 4096
        {
            return Err("invalid translation provider buffer".into());
        }
        let query = serde_json::from_slice::<TranslationQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid translation query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .translate(query)
            .map(|items| json!({"translations": items}))
            .unwrap_or(Value::Null))
    })
}

/// Query a user-owned Linux handwriting recognizer over a Unix socket.
/// The request is a bounded JSON HandwritingQuery; the response is
/// `{candidates:[...]}` or null when the recognizer is unavailable.
///
/// # Safety
/// All pointers must reference readable buffers of the stated lengths for
/// the duration of this call; the buffers are not retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_handwriting_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null()
            || socket_path.is_null()
            || query_length > 262_144
            || socket_length > 4096
        {
            return Err("invalid handwriting provider buffer".into());
        }
        let query = serde_json::from_slice::<HandwritingQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid handwriting query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .handwriting(query)
            .map(|candidates| json!({"candidates": candidates}))
            .unwrap_or(Value::Null))
    })
}

/// Run the Engine's optional offline handwriting recognizer against a trusted
/// packaged model. The model path is supplied by the native host, never by a
/// webview or remote provider.
///
/// # Safety
/// The caller must provide non-null readable buffers of the stated lengths. The buffers are read
/// only for the duration of this call and are never retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_handwriting_local_request(
    query: *const u8,
    query_length: usize,
    model_path: *const u8,
    model_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || model_path.is_null() || query_length > 262_144 || model_length > 4096
        {
            return Err("invalid local handwriting buffer".into());
        }
        let query = serde_json::from_slice::<HandwritingQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid handwriting query document")?;
        let model =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(model_path, model_length) })
                .map_err(|_| "model path is not UTF-8")?;
        if !std::path::Path::new(model).is_absolute() {
            return Err("model path must be absolute".into());
        }
        let candidates = engine_handwriting_candidates(model, &query, 1.0, 1.0)?;
        Ok(json!({"candidates": candidates}))
    })
}

/// Query a user-owned Linux emoji catalog over a Unix socket.
/// The response is `{items:[{text,annotation}]}` or null when unavailable.
///
/// # Safety
/// All pointers must reference readable buffers of the stated lengths for
/// the duration of this call; the buffers are not retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_emoji_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096
        {
            return Err("invalid emoji provider buffer".into());
        }
        let query = serde_json::from_slice::<EmojiPanelQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid emoji query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .emoji(query)
            .map(|items| json!({"items": items}))
            .unwrap_or(Value::Null))
    })
}

#[cfg(unix)]
#[derive(Deserialize)]
struct EmojiCatalogQuery {
    #[serde(flatten)]
    panel: EmojiPanelQuery,
    #[serde(default)]
    offset: usize,
    #[serde(default)]
    group: String,
    #[serde(default)]
    list_groups: bool,
    #[serde(default)]
    list_symbol_groups: bool,
    #[serde(default)]
    parent: String,
    #[serde(default)]
    cursor: bool,
}

/// Query the local verified `others.db` Emoji catalog without a provider socket.
/// Success contains `{items:[{text,annotation,group}]}` in the response envelope.
/// With `cursor:true`, also returns `next_offset` and `complete`, preserves
/// duplicate entries, and advances past invalid rows without treating them as EOF.
/// Unavailable or unreadable catalogs return an error, not an empty item list.
///
/// # Safety
/// All pointers must reference readable buffers of the stated lengths for
/// the duration of this call; the buffers are not retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_emoji_catalog_request(
    query: *const u8,
    query_length: usize,
    resources: *const u8,
    resources_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null()
            || resources.is_null()
            || query_length > 16_384
            || resources_length > 4096
        {
            return Err("invalid local emoji buffer".into());
        }
        let query = serde_json::from_slice::<EmojiCatalogQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid emoji query document")?;
        let resources =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(resources, resources_length) })
                .map_err(|_| "resources path is not UTF-8")?;
        if !std::path::Path::new(resources).is_absolute() {
            return Err("resources path must be absolute".into());
        }
        if query.offset > i64::MAX as usize || query.panel.limit == 0 {
            return Err("invalid emoji page".into());
        }
        if query.list_groups {
            let groups =
                msime_engine_bridge::emoji_catalog_groups(resources, &query.panel.category)
                    .map_err(|_| "local emoji catalog unavailable")?;
            return Ok(json!({"groups": groups}));
        }
        if query.list_symbol_groups {
            let groups = msime_engine_bridge::emoji_symbol_groups(resources)
                .map_err(|_| "local emoji catalog unavailable")?;
            return Ok(
                json!({"symbol_groups": groups.into_iter().map(|g| json!({"parent":g.parent,"title":g.title})).collect::<Vec<_>>()}),
            );
        }
        if !query.parent.is_empty() && query.panel.category != "symbols" {
            return Err("parent filter requires symbols catalog".into());
        }
        if query.cursor {
            let slice = msime_engine_bridge::emoji_catalog_slice(
                resources,
                &query.panel.search,
                &query.panel.category,
                &query.group,
                query.offset,
                u16::from(query.panel.limit),
                &query.parent,
            )
            .map_err(|_| "local emoji catalog unavailable")?;
            return Ok(json!({
                "items": slice.items.into_iter().map(|item| json!({
                    "text": item.text, "annotation": item.annotation, "group": item.group,
                })).collect::<Vec<_>>(),
                "next_offset": slice.next_offset,
                "complete": slice.complete,
            }));
        }
        let items = msime_engine_bridge::emoji_catalog_parent_page(
            resources,
            &query.panel.search,
            &query.panel.category,
            &query.group,
            query.offset,
            u16::from(query.panel.limit),
            &query.parent,
        )
        .map_err(|_| "local emoji catalog unavailable")?;
        Ok(json!({
            "items": items
                .into_iter()
                .map(|item| {
                    json!({
                        "text": item.text,
                        "annotation": item.annotation,
                        "group": item.group,
                    })
                })
                .collect::<Vec<_>>()
        }))
    })
}

/// Decode one Doubao v1 response frame for Apple hosts. The returned payload
/// is UTF-8 JSON text; no frame bytes or credentials are retained.
///
/// # Safety
/// `frame` must reference a readable buffer for the duration of this call.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_decode_frame(
    frame: *const u8,
    frame_length: usize,
) -> *mut c_char {
    response(|| {
        if frame.is_null() || frame_length == 0 || frame_length > 1_048_576 {
            return Err("invalid Doubao frame buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(frame, frame_length) };
        if let Some((last, _sequence, payload)) = decode_json_frame(bytes) {
            let text = String::from_utf8(payload).map_err(|_| "Doubao payload is not UTF-8")?;
            return Ok(json!({ "last": last, "payload": text }));
        }
        if let Some(code) = decode_error_code(bytes) {
            return Ok(json!({ "error_code": code }));
        }
        Err("invalid Doubao response frame".into())
    })
}

unsafe fn write_doubao_frame(
    frame: Vec<u8>,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if output.is_null() || output_length.is_null() {
        return false;
    }
    *output_length = frame.len();
    if frame.len() > output_capacity {
        return false;
    }
    std::ptr::copy_nonoverlapping(frame.as_ptr(), output, frame.len());
    true
}

/// Build a Doubao start request into caller-owned storage.
///
/// # Safety
/// `boosting_table_id` must point to `boosting_table_id_length` readable bytes when the length is
/// nonzero. `output` must point to `output_capacity` writable bytes and `output_length` must point
/// to a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_start_frame(
    enable_itn: bool,
    enable_punc: bool,
    enable_ddc: bool,
    boosting_table_id: *const u8,
    boosting_table_id_length: usize,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if boosting_table_id_length > 4096
        || (boosting_table_id.is_null() && boosting_table_id_length != 0)
    {
        return false;
    }
    let boosting = if boosting_table_id_length == 0 {
        ""
    } else {
        let bytes =
            unsafe { std::slice::from_raw_parts(boosting_table_id, boosting_table_id_length) };
        match std::str::from_utf8(bytes) {
            Ok(value) => value,
            Err(_) => return false,
        }
    };
    unsafe {
        write_doubao_frame(
            start_frame(enable_itn, enable_punc, enable_ddc, boosting),
            output,
            output_capacity,
            output_length,
        )
    }
}

/// Build a Doubao PCM or final audio frame into caller-owned storage.
///
/// # Safety
/// `pcm` must point to `pcm_length` readable bytes when the length is nonzero. `output` must point
/// to `output_capacity` writable bytes and `output_length` must point to a writable `usize`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_doubao_audio_frame(
    sequence: i32,
    pcm: *const u8,
    pcm_length: usize,
    final_chunk: bool,
    output: *mut u8,
    output_capacity: usize,
    output_length: *mut usize,
) -> bool {
    if pcm_length > 1_048_576 || (pcm.is_null() && pcm_length != 0) {
        return false;
    }
    let bytes = if pcm_length == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(pcm, pcm_length) }
    };
    unsafe {
        write_doubao_frame(
            audio_frame(sequence, bytes, final_chunk),
            output,
            output_capacity,
            output_length,
        )
    }
}

/// Run one bounded voice capture/ASR request through a user-owned Unix socket.
/// The socket service owns microphone access, credentials and network policy.
/// The query is a bounded JSON object containing `language`, `generation`,
/// and optional non-sensitive voice behavior `options`.
///
/// # Safety
/// All pointers must reference readable buffers of the stated lengths for
/// the duration of this call; the buffers are not retained.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_request(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096
        {
            return Err("invalid voice provider buffer".into());
        }
        #[derive(Deserialize)]
        struct VoiceQuery {
            language: String,
            generation: u64,
            #[serde(default)]
            options: Value,
        }
        let query = serde_json::from_slice::<VoiceQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid voice query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(UnixSocketProvider::new(path)
            .voice_with_options(&query.language, query.generation, &query.options)
            .map(|text| json!({"text": text}))
            .unwrap_or(Value::Null))
    })
}

/// Stream bounded interim/final voice provider updates from a user-owned
/// Unix socket. The callback is invoked synchronously on the calling thread.
///
/// # Safety
/// Buffers must remain readable for the duration of this call. The callback
/// must remain valid and must copy the text before returning.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    unsafe {
        msime_client_voice_provider_stream_events(
            query,
            query_length,
            socket_path,
            socket_length,
            callback,
            None,
            context,
        )
    }
}

/// Stream voice text and optional phase notifications (0 recording, 1 recognizing, 2 polishing).
///
/// # Safety
/// Buffers and callbacks must remain valid for this synchronous call. Callbacks must not unwind.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream_events(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    status_callback: Option<unsafe extern "C" fn(u8, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    unsafe {
        msime_client_voice_provider_stream_feedback(
            query,
            query_length,
            socket_path,
            socket_length,
            callback,
            status_callback,
            None,
            context,
        )
    }
}

/// Stream voice text, phases and optional normalized microphone levels.
///
/// # Safety
/// Buffers and callbacks must remain valid for this synchronous call. Callbacks must not unwind.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stream_feedback(
    query: *const u8,
    query_length: usize,
    socket_path: *const u8,
    socket_length: usize,
    callback: Option<unsafe extern "C" fn(*const u8, usize, bool, *mut c_void)>,
    status_callback: Option<unsafe extern "C" fn(u8, *mut c_void)>,
    level_callback: Option<unsafe extern "C" fn(f32, *mut c_void)>,
    context: *mut c_void,
) -> *mut c_char {
    response(|| {
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096
        {
            return Err("invalid voice provider buffer".into());
        }
        #[derive(Deserialize)]
        struct VoiceQuery {
            language: String,
            generation: u64,
            #[serde(default)]
            options: Value,
        }
        let query = serde_json::from_slice::<VoiceQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid voice query document")?;
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        let mut update = |text: &str, final_result: bool| {
            if let Some(callback) = callback {
                unsafe {
                    callback(text.as_ptr(), text.len(), final_result, context);
                }
            }
        };
        let mut status = |phase: &str| {
            if let Some(callback) = status_callback {
                let value = match phase {
                    "recording" => 0,
                    "recognizing" => 1,
                    "polishing" => 2,
                    _ => return,
                };
                unsafe {
                    callback(value, context);
                }
            }
        };
        let mut level = |value: f32| {
            if let Some(callback) = level_callback {
                unsafe {
                    callback(value, context);
                }
            }
        };
        let value = UnixSocketProvider::new(path).voice_stream_with_options_feedback(
            &query.language,
            query.generation,
            &query.options,
            None,
            &mut update,
            if status_callback.is_some() {
                Some(&mut status)
            } else {
                None
            },
            if level_callback.is_some() {
                Some(&mut level)
            } else {
                None
            },
        );
        Ok(value
            .map(|text| json!({"text": text}))
            .unwrap_or(Value::Null))
    })
}

/// Ask a user-owned Unix socket to stop voice capture for one generation.
///
/// # Safety
/// `socket_path` must reference a readable UTF-8 buffer for this call.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_cancel(
    socket_path: *const u8,
    socket_length: usize,
    generation: u64,
) -> *mut c_char {
    response(|| {
        if socket_path.is_null() || socket_length > 4096 {
            return Err("invalid voice provider socket buffer".into());
        }
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(json!(UnixSocketProvider::new(path).voice_cancel(generation)))
    })
}

/// Ask a user-owned voice socket to finish capture and return its final stream
/// result. The streaming connection remains responsible for delivering text.
///
/// # Safety
/// `socket_path` must reference a readable UTF-8 buffer for this call.
#[cfg(unix)]
#[no_mangle]
pub unsafe extern "C" fn msime_client_voice_provider_stop(
    socket_path: *const u8,
    socket_length: usize,
    generation: u64,
) -> *mut c_char {
    response(|| {
        if socket_path.is_null() || socket_length > 4096 {
            return Err("invalid voice provider socket buffer".into());
        }
        let path =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(socket_path, socket_length) })
                .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(json!(UnixSocketProvider::new(path).voice_stop(generation)))
    })
}

/// Apply a provider result returned for a previously copied OnlineQuery.
/// The query and candidate buffers are UTF-8 and are never retained.
///
/// # Safety
/// The caller must provide readable buffers of the stated lengths, or null pointers only with
/// zero lengths; buffers are read for the duration of this call and never retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_apply_online_candidate(
    handle: u64,
    query: *const u8,
    query_length: usize,
    candidate: *const u8,
    candidate_length: usize,
    source: u8,
) -> *mut c_char {
    response(|| {
        if query.is_null() || candidate.is_null() || query_length > 16384 || candidate_length > 4096
        {
            return Err("invalid online candidate buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let candidate =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(candidate, candidate_length) })
                .map_err(|_| "candidate is not UTF-8")?;
        with_session(handle, |session| {
            if source == 1 && !session.ai_query_is_current(&query) {
                return Ok(json!({"applied":false,"view":session.runtime.view()}));
            }
            let applied = session
                .runtime
                .apply_online_candidate(&query, candidate, source)
                .map_err(|e| e.to_string())?;
            Ok(json!({ "applied": applied, "view": session.runtime.view() }))
        })
    })
}

/// Parse a bounded host-fetched cloud response and apply it to its original query.
/// Invalid/no-result provider documents leave the current view unchanged.
///
/// # Safety
/// Both pointers must reference readable buffers of their stated lengths.
#[no_mangle]
pub unsafe extern "C" fn msime_client_apply_cloud_response(
    handle: u64,
    query: *const u8,
    query_length: usize,
    body: *const u8,
    body_length: usize,
) -> *mut c_char {
    response(|| {
        if query.is_null() || body.is_null() || query_length > 16384 || body_length > 262144 {
            return Err("invalid cloud response buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let candidate = msime_input_runtime::cloud_candidate_from_response(query, unsafe {
            std::slice::from_raw_parts(body, body_length)
        });
        with_session(handle, |session| {
            let applied = if session.cloud_candidates_enabled() {
                if let Some(candidate) = candidate {
                    session
                        .runtime
                        .apply_online_candidate(&candidate.query, &candidate.text, candidate.source)
                        .map_err(|e| e.to_string())?
                } else {
                    false
                }
            } else {
                false
            };
            Ok(json!({ "applied": applied, "view": session.runtime.view() }))
        })
    })
}

/// Apply an ordered JSON array of candidate strings for one online source.
///
/// # Safety
/// Both pointers must reference readable buffers of their stated lengths.
#[no_mangle]
pub unsafe extern "C" fn msime_client_apply_online_candidates(
    handle: u64,
    query: *const u8,
    query_length: usize,
    candidates: *const u8,
    candidates_length: usize,
    source: u8,
) -> *mut c_char {
    response(|| {
        if query.is_null()
            || candidates.is_null()
            || query_length > 16384
            || candidates_length > 16384
            || source > 1
        {
            return Err("invalid online candidates buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let candidates = serde_json::from_slice::<Vec<String>>(unsafe {
            std::slice::from_raw_parts(candidates, candidates_length)
        })
        .map_err(|_| "invalid online candidates document")?;
        with_session(handle, |session| {
            if source == 1 && !session.ai_query_is_current(&query) {
                return Ok(json!({"applied":false,"view":session.runtime.view()}));
            }
            let applied = session
                .runtime
                .apply_online_candidates(&query, &candidates, source)
                .map_err(|e| e.to_string())?;
            Ok(json!({ "applied": applied, "view": session.runtime.view() }))
        })
    })
}

/// Select one Han edge through Engine using the displayed candidate identity.
#[no_mangle]
pub extern "C" fn msime_client_select_edge(
    handle: u64,
    generation: u64,
    index: usize,
    edge: u8,
) -> *mut c_char {
    let edge = match edge {
        0 => CandidateEdge::FirstHan,
        1 => CandidateEdge::LastHan,
        _ => return response(|| Err("Invalid candidate edge".into())),
    };
    dispatch(
        handle,
        Action::SelectEdge(
            CandidateId {
                session: handle,
                generation,
                index,
            },
            edge,
        ),
    )
}

/// Queue a validated preference snapshot without interrupting composition.
/// # Safety
/// `snapshot` must point to `length` readable bytes for this call. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_update_preferences(
    handle: u64,
    snapshot: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if snapshot.is_null() || length > 16384 {
            return Err("invalid preferences buffer".into());
        }
        // SAFETY: guaranteed by the caller's buffer contract.
        let bytes = unsafe { std::slice::from_raw_parts(snapshot, length) };
        let snapshot = serde_json::from_slice(bytes).map_err(|_| "invalid preferences document")?;
        with_session(handle, |session| session.update(snapshot))
    })
}

#[no_mangle]
pub extern "C" fn msime_client_destroy(handle: u64) -> *mut c_char {
    response(|| {
        SESSIONS.with(|sessions| {
            sessions
                .try_borrow_mut()
                .map_err(|_| "reentrant host call")?
                .remove(&handle)
                .ok_or("unknown session or wrong thread")?;
            Ok(Value::Null)
        })
    })
}

/// # Safety
/// `value` must be null or an allocation returned by this library, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn msime_client_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: ownership is transferred back exactly once by the C caller.
        drop(unsafe { CString::from_raw(value) });
    }
}

#[cfg(test)]
mod tests;

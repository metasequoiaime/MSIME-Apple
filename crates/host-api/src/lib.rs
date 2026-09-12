//! Versioned, thread-confined C interface for native IME hosts.
//! A handle registry rejects stale and wrong-thread handles without dereferencing them.

use msime_client_core::dictionary_access::DictionaryAccess;
pub mod cloud_clipboard;
pub mod cloud_dictionary;
pub mod system_fonts;
use msime_client_core::preferences::{
    InputScheme, Preferences, PreferencesSnapshot, PreferencesStore, ShuangpinProfile,
    TouchKeyboardLayout,
};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_client_core::voice::VoiceSessionState;
use msime_engine_bridge::{CandidateEdge, Command, EngineOptions, Session};
#[cfg(unix)]
use msime_input_runtime::{EmojiPanelQuery, HandwritingQuery, TranslationQuery};
#[cfg(unix)]
use msime_input_runtime::UnixSocketProvider;
use msime_input_runtime::{
    AiAssistantProviderConfig, Action, CandidateId, CharacterWidth, NineKeySpellingId, OnlineQuery,
    Runtime, Transition,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
mod dictionary;
pub use dictionary::{dictionary_request_json, msime_client_dictionary};
mod dictionary_snapshot;
pub use dictionary_snapshot::{
    msime_client_snapshot_discard, msime_client_snapshot_prepare, msime_client_snapshot_version,
};

/// Run the optional offline Engine handwriting recognizer for a native panel.
/// The caller must provide a trusted absolute model path; strokes are copied
/// before crossing the C++ bridge. The shared Linux panel uses a 420 by 420
/// canvas, which is also the coordinate space passed to the Engine.
#[cfg(unix)]
pub fn handwriting_local_candidates(
    model_path: &str,
    query: &HandwritingQuery,
) -> Result<Vec<String>, &'static str> {
    if !std::path::Path::new(model_path).is_absolute() {
        return Err("model path must be absolute");
    }
    let strokes = query
        .strokes
        .iter()
        .map(|stroke| stroke.iter().map(|point| (point.x, point.y)).collect())
        .collect::<Vec<Vec<(f32, f32)>>>();
    msime_engine_bridge::handwriting_recognize(model_path, &strokes, 420.0, 420.0)
        .map_err(|_| "local handwriting recognizer unavailable")
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
}

impl HostSession {
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
        options.learning = snapshot.preferences.learning;
        options.autocorrect = snapshot.preferences.autocorrect;
        options.frequency_mode = snapshot.preferences.frequency.mode.as_str().into();
        options.frequency_trigger_count = snapshot.preferences.frequency.trigger_count;
        options.frequency_linear_step = snapshot.preferences.frequency.linear_step;
        options.mixed_english = snapshot.preferences.mixed_input.english;
        options.english_minimum_prefix = snapshot.preferences.mixed_input.minimum_prefix;
        options.mixed_emoji = snapshot.preferences.mixed_input.emoji;
        options.mixed_kaomoji = snapshot.preferences.mixed_input.kaomoji;
        let helpcode = snapshot.preferences.active_helpcode();
        options.helpcode = helpcode.enabled;
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
}

impl HostOptions {
    fn into_engine_options(self) -> EngineOptions {
        let helpcode = self.preferences.active_helpcode();
        EngineOptions {
            resources: self.resources,
            user_data: self.user_data,
            cache: self.cache,
            dictionaries: self.dictionaries,
            scheme: scheme_code(self.preferences.scheme),
            shuangpin_profile: profile_code(self.preferences.shuangpin_profile),
            learning: self.preferences.learning,
            autocorrect: self.preferences.autocorrect,
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
            helpcode: helpcode.enabled,
            helpcode_schema: helpcode.schema.as_str().into(),
            chinese_punctuation: self.preferences.chinese_punctuation,
            paired_punctuation: self.preferences.paired_punctuation,
            punctuation_lock: match self.preferences.punctuation_lock {
                msime_client_core::preferences::PunctuationLock::Follow => 0,
                msime_client_core::preferences::PunctuationLock::Chinese => 1,
                msime_client_core::preferences::PunctuationLock::English => 2,
            },
        }
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
    let preferences = PreferencesStore::new(&state_root).load()?.preferences;
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
    })?)
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

/// Read one bounded page from the Engine-owned `others.db` catalog.
#[cfg(unix)]
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
    1
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
        let saved = PreferencesStore::new(directory)
            .save(expected_revision, snapshot.preferences)
            .map_err(|e| e.to_string())?;
        serde_json::to_value(saved).map_err(|e| e.to_string())
    })
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
        let helpcode = options.preferences.active_helpcode();
        let options = EngineOptions {
            resources: options.resources,
            user_data: options.user_data,
            cache: options.cache,
            dictionaries: options.dictionaries,
            scheme: scheme_code(options.preferences.scheme),
            shuangpin_profile: profile_code(options.preferences.shuangpin_profile),
            learning: options.preferences.learning,
            autocorrect: options.preferences.autocorrect,
            frequency_mode: options.preferences.frequency.mode.as_str().into(),
            frequency_trigger_count: options.preferences.frequency.trigger_count,
            frequency_linear_step: options.preferences.frequency.linear_step,
            mixed_english: options.preferences.mixed_input.english,
            english_minimum_prefix: options.preferences.mixed_input.minimum_prefix,
            mixed_emoji: options.preferences.mixed_input.emoji,
            mixed_kaomoji: options.preferences.mixed_input.kaomoji,
            local_unicode: options.preferences.local_modes.unicode,
            local_date_time: options.preferences.local_modes.date_time,
            local_quick_phrase: options.preferences.local_modes.quick_phrase,
            local_emoji: options.preferences.local_modes.emoji,
            local_kaomoji: options.preferences.local_modes.kaomoji,
            local_super_jianpin: options.preferences.local_modes.super_jianpin,
            local_temporary_english: options.preferences.local_modes.temporary_english,
            local_temporary_japanese: options.preferences.local_modes.temporary_japanese,
            helpcode: helpcode.enabled,
            helpcode_schema: helpcode.schema.as_str().into(),
            chinese_punctuation: options.preferences.chinese_punctuation,
            paired_punctuation: options.preferences.paired_punctuation,
            punctuation_lock: match options.preferences.punctuation_lock {
                msime_client_core::preferences::PunctuationLock::Follow => 0,
                msime_client_core::preferences::PunctuationLock::Chinese => 1,
                msime_client_core::preferences::PunctuationLock::English => 2,
            },
        };
        let default_english = matches!(
            applied.default_ime_mode,
            msime_client_core::preferences::DefaultImeMode::English
        );
        let mut engine = Session::new(&options).map_err(|e| e.to_string())?;
        let default_nine_key = matches!(applied.scheme, InputScheme::Quanpin)
            && matches!(applied.touch_keyboard_layout, TouchKeyboardLayout::NineKey);
        if default_nine_key {
            engine
                .set_nine_key_enabled(true)
                .map_err(|e| e.to_string())?;
        }
        engine
            .set_dedicated_english(default_english)
            .map_err(|e| e.to_string())?;
        let runtime =
            Runtime::new_with_touch_layout(engine, page_size, applied.touch_keyboard_layout)
                .map_err(|e| e.to_string())?;
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
                    english_mode: default_english,
                    page_size_override: None,
                    nine_key_override: None,
                    voice: VoiceSessionState::default(),
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
            || values
                .iter()
                .any(|item| item.text.len() > 4096 || item.translation.len() > 4096)
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
            value["cloud_candidates"] = Value::Bool(session.applied.cloud_candidates);
            let ai = &session.applied.ai_assistant;
            if ai.enabled {
                value["ai_assistant"] = serde_json::to_value(AiAssistantProviderConfig {
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
                .map_err(|e| e.to_string())?;
            }
            Ok(value)
        })
    })
}

/// Return the visible candidate texts that may receive asynchronous translations.
/// The generation must be echoed to `msime_client_apply_translations`.
#[no_mangle]
pub extern "C" fn msime_client_translation_query(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            if !session.applied.candidate_translations {
                return Ok(Value::Null);
            }
            let view = session.runtime.view();
            if view.candidates.is_empty() {
                return Ok(Value::Null);
            }
            let candidates = view
                .candidates
                .iter()
                .map(|candidate| json!({ "text": candidate.text }))
                .collect::<Vec<_>>();
            let custom_translation = &session.applied.custom_translation;
            let custom_translation = (custom_translation.enabled
                && !custom_translation.endpoint.is_empty())
                .then(|| {
                    json!({
                        "enabled": true,
                        "endpoint": &custom_translation.endpoint,
                        "api_key": &custom_translation.api_key,
                    })
                });
            Ok(json!({
                "generation": view.generation,
                "target_language": serde_json::to_value(session.applied.translation_target_language)
                    .map_err(|e| e.to_string())?,
                "candidates": candidates,
                "custom_translation": custom_translation,
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
            .query(query)
            .map(|(text, source)| json!({"text": text, "source": source}))
            .unwrap_or(Value::Null))
    })
}

/// Forward one account-backed dictionary operation to a user-owned Linux
/// provider. The request is validated before it crosses the Unix socket.
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
        let strokes: Vec<Vec<(f32, f32)>> = query
            .strokes
            .iter()
            .map(|stroke| stroke.iter().map(|point| (point.x, point.y)).collect())
            .collect();
        let candidates = msime_engine_bridge::handwriting_recognize(model, &strokes, 1.0, 1.0)
            .map_err(|_| "local handwriting recognizer unavailable")?;
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
}

/// Query the local verified `others.db` Emoji catalog without a provider socket.
/// Success contains `{items:[{text,annotation,group}]}` in the response envelope.
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
        let items = msime_engine_bridge::emoji_catalog_filtered_page(
            resources,
            &query.panel.search,
            &query.panel.category,
            &query.group,
            query.offset,
            u16::from(query.panel.limit),
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
        if query.is_null() || socket_path.is_null() || query_length > 16_384 || socket_length > 4096 {
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
    response(|| {
        if query.is_null()
            || socket_path.is_null()
            || query_length > 16_384
            || socket_length > 4096
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
        let path = std::str::from_utf8(unsafe {
            std::slice::from_raw_parts(socket_path, socket_length)
        })
        .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        let mut update = |text: &str, final_result: bool| {
            if let Some(callback) = callback {
                unsafe {
                    callback(
                        text.as_ptr(),
                        text.len(),
                        final_result,
                        context,
                    );
                }
            }
        };
        let value = UnixSocketProvider::new(path).voice_stream_with_options_cancelled(
            &query.language,
            query.generation,
            &query.options,
            None,
            &mut update,
        );
        Ok(value.map(|text| json!({"text": text})).unwrap_or(Value::Null))
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
        let path = std::str::from_utf8(unsafe {
            std::slice::from_raw_parts(socket_path, socket_length)
        })
        .map_err(|_| "socket path is not UTF-8")?;
        if !std::path::Path::new(path).is_absolute() {
            return Err("socket path must be absolute".into());
        }
        Ok(json!(UnixSocketProvider::new(path).voice_cancel(generation)))
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
            let applied = session
                .runtime
                .apply_online_candidate(&query, candidate, source)
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
mod tests {
    use super::*;
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
        SESSIONS.with(|sessions| assert!(sessions.borrow()[&handle].options.mixed_english));
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
        SESSIONS.with(|sessions| {
            assert_eq!(sessions.borrow()[&handle].options.frequency_mode, "promote")
        });
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
    fn japanese_mode_switch_defers_and_restores_chinese_profile() {
        use msime_client_core::preferences::ChineseScheme;
        let dir = tempfile::tempdir().unwrap();
        let chinese = Preferences {
            scheme: InputScheme::Shuangpin,
            shuangpin_profile: ShuangpinProfile::Microsoft,
            last_chinese_scheme: Some(ChineseScheme::Shuangpin),
            ..Preferences::default()
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
        assert_eq!(kana["value"]["view"]["scheme"], 3);
        assert_eq!(kana["value"]["view"]["candidates"][0]["text"], "あ");
        assert_eq!(kana["value"]["view"]["candidates"][1]["text"], "ア");
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
                show_in_candidate_window: true,
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
        });
        preferences.scheme = InputScheme::Shuangpin;
        assert_eq!(update(handle, 2, &preferences)["value"]["deferred"], false);
        SESSIONS.with(|sessions| {
            assert!(sessions.borrow()[&handle].options.helpcode);
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
            autocorrect: false,
            ..Preferences::default()
        };
        assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
        assert_eq!(read(msime_client_view(handle))["value"], before);
        SESSIONS.with(|sessions| assert!(sessions.borrow()[&handle].options.autocorrect));
        read(msime_client_command(handle, 3));
        SESSIONS.with(|sessions| assert!(!sessions.borrow()[&handle].options.autocorrect));
        assert_eq!(
            update(handle, 2, &Preferences::default())["value"]["deferred"],
            false
        );
        SESSIONS.with(|sessions| assert!(sessions.borrow()[&handle].options.autocorrect));
        read(msime_client_destroy(handle));
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
    fn test_host(root: &std::path::Path) -> u64 {
        test_host_preferences(root, Preferences::default())
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
    fn update(handle: u64, revision: u64, preferences: &Preferences) -> Value {
        let snapshot =
            json!({ "format_version": 1, "revision": revision, "preferences": preferences })
                .to_string();
        read(unsafe { msime_client_update_preferences(handle, snapshot.as_ptr(), snapshot.len()) })
    }

    #[test]
    fn shuangpin_profile_creation_and_deferred_replacement_use_real_engine() {
        let dir = tempfile::tempdir().unwrap();
        let microsoft = Preferences {
            scheme: InputScheme::Shuangpin,
            shuangpin_profile: ShuangpinProfile::Microsoft,
            ..Preferences::default()
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
                std::thread::spawn(
                    move || read(msime_client_punctuation(handle, b','))["ok"].clone()
                )
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
    fn candidate_edge_uses_engine_han_text_and_preserves_unsupported_composition() {
        for (code, first, last) in [("4e2d", "中", "中"), ("20000", "𠀀", "𠀀"), ("41", "", "")]
        {
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
        assert_eq!(
            read(msime_client_set_english_mode(handle, false))["ok"],
            true
        );
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
        let options = json!({ "api_version": 1, "resources": path("resources"), "user_data": path("user"), "cache": path("cache"), "dictionaries": path("dictionaries"), "preferences": { "scheme": "quanpin", "candidate_page_size": 5, "learning": false, "chinese_punctuation": true } }).to_string();
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
    #[cfg(unix)]
    fn emoji_catalog_pagination_preserves_legacy_defaults() {
        let legacy: EmojiCatalogQuery = serde_json::from_str("{}").unwrap();
        assert_eq!(legacy.offset, 0);
        assert_eq!(legacy.panel.limit, 48);
        let page: EmojiCatalogQuery = serde_json::from_str(
            r#"{"search":"synthetic","category":"symbols","offset":510,"limit":255}"#,
        )
        .unwrap();
        assert_eq!(page.offset, 510);
        assert_eq!(page.panel.search, "synthetic");
        assert_eq!(page.panel.category, "symbols");
        assert_eq!(page.panel.limit, 255);
        assert!(serde_json::from_str::<EmojiCatalogQuery>(r#"{"offset":-1}"#).is_err());
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
            let page = request(
                json!({"category":category,"group":"Z","search":"match","offset":1,"limit":1}),
            );
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
        db.execute_batch("DROP TABLE emoji").unwrap();
        assert_eq!(request(json!({"list_groups":true}))["ok"], false);
    }
}

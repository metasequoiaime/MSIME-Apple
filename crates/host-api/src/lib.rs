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
use msime_client_core::resources::{ResourceSet, ResourceStore, VerifiedMarker};
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
// The exports live in `ffi`, but Rust consumers - this crate's own tests and
// examples, and anything linking the rlib - have always reached them at the
// crate root. Re-exported so moving the file changes no caller.
mod ffi;
pub use ffi::*;
mod doubao_auth;
pub use doubao_auth::msime_client_doubao_auth_headers;
mod learned_translation;
mod niutrans_translation;
mod tencent_translation;
pub use dictionary::{
    dictionary_request_json, msime_client_dictionary, msime_client_dictionary_validate,
    msime_client_personal_dictionary_request, msime_client_personal_dictionary_sync,
    personal_dictionary_request_json,
};
mod dictionary_snapshot;
pub use dictionary_snapshot::{
    msime_client_snapshot_discard, msime_client_snapshot_inspect, msime_client_snapshot_prepare,
    msime_client_snapshot_queue, msime_client_snapshot_version,
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

#[derive(Clone, Deserialize, Serialize)]
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
    /// The host draws a half-composed phrase itself: picking a candidate that covers only part of
    /// the input leaves the chosen piece in `view.phrase_prefix` instead of committing it, and the
    /// whole phrase commits at once when the composition ends. Absent means the previous behaviour,
    /// where each piece went to the document as it was picked, because a host that does not draw
    /// the field would otherwise show nothing for it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    phrase_preedit: Option<bool>,
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
    /// Absolute path to the larger model run once typing settles, for hosts that install one.
    ///
    /// Its own option rather than an entry in the dictionary lock, because the lock is shared by
    /// every platform and `ResourceStore::verify` requires a resource directory to match it
    /// exactly — a desktop-only artifact there would mean teaching the manifest, the Rust
    /// verifier, the PowerShell verifier, four staging scripts and a CMake parser what a platform
    /// is, all on the path that guarantees a shipped dictionary is intact. Twenty five megabytes
    /// inside an iOS keyboard extension is also precisely what the small preset exists to avoid.
    ///
    /// A host that wants the second model installs it where it likes and names it here; one that
    /// does not leaves this absent and behaves exactly as before. Today that is every host: the
    /// desktop platforms are the ones this is for, and they set it alongside shipping the file.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    settled_model: Option<String>,
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
/// The settled-rerank model installed beside a resource bundle, when one is there.
///
/// A sibling directory rather than a file inside `resources`, because that directory is verified
/// against `desktop-dictionary.lock.json` and must match it *exactly* — an extra file there fails
/// the check whose job is to prove a shipped dictionary is intact. The lock is also shared by all
/// six platforms, and this model is wanted by three: it buys 49 points of top-1 on the harvested
/// failure set and costs p95 153ms per keystroke, which is why it runs on the settle timer, and
/// why 25MB of it has no business inside an iOS keyboard extension.
///
/// Absence is the normal case and is not an error. A host that installs the model puts it here;
/// one that does not is left exactly as it was.
fn settled_model_beside(resources: &std::path::Path) -> Option<String> {
    let path = resources
        .parent()?
        .join("settled-model")
        .join("sentence-model-desktop.safetensors");
    path.is_file().then(|| path.to_str())??.to_owned().into()
}

/// Drop the `\\?\` prefix Windows canonicalisation adds.
///
/// The Engine validates the directories it is given with `std::filesystem::path::is_absolute`, and
/// libstdc++ reads a verbatim path as having no root name - so `\\?\Z:\res` is not absolute to it
/// and preparation is refused. MSVC's standard library parses the prefix, which is why a build with
/// it never sees this; the GNU cross build, and every test that runs those binaries, does.
///
/// Only the drive form is unwrapped. `\\?\UNC\server\share` means something different from
/// `\\server\share` to the filesystem, so it is left alone rather than rewritten into a path that
/// happens to parse.
fn without_verbatim_prefix(path: std::path::PathBuf) -> std::path::PathBuf {
    let text = match path.to_str() {
        Some(text) => text,
        None => return path,
    };
    let stripped = match text.strip_prefix(r"\\?\") {
        Some(stripped) => stripped,
        None => return path,
    };
    let drive = stripped.as_bytes();
    if drive.len() >= 3 && drive[0].is_ascii_alphabetic() && drive[1] == b':' && drive[2] == b'\\' {
        return std::path::PathBuf::from(stripped);
    }
    path
}

/// Hash the resource set unless the last successful verification still describes what is on disk.
///
/// This runs at every Server start, and the desktop set is 169 MB: about half a second of SHA-256
/// before the first keystroke can be served, repeated at every login. `VerifiedMarker` records what
/// was verified so the repeat is skipped while the files are untouched, in the same shape
/// `scripts/fetch_engine.py` already uses for the Engine archive.
///
/// The marker lives under the state root rather than beside the resources: on Windows the
/// resources are installed under Program Files, which the Server does not get to write to.
///
/// Failing to write the marker is not failing to start. The next launch hashes again, which is the
/// behaviour this function replaces, so the cost of that miss is the cost of doing nothing here.
fn verify_resources_once(
    resources: &std::path::Path,
    specification: &ResourceSet,
    state_root: &std::path::Path,
) -> Result<(), Box<dyn std::error::Error>> {
    let marker_path = state_root.join("verified-resources.json");
    let current = VerifiedMarker::describe(resources, specification)?;
    if let (Some(current), Some(recorded)) = (&current, VerifiedMarker::read(&marker_path)) {
        if *current == recorded {
            return Ok(());
        }
    }
    ResourceStore::new(resources).verify(resources, specification)?;
    if let Some(current) = current {
        let _ = current.write(&marker_path);
    }
    Ok(())
}

pub fn prepare_host_configuration(
    resources: &std::path::Path,
    state_root: &std::path::Path,
) -> Result<String, Box<dyn std::error::Error>> {
    let resources = without_verbatim_prefix(std::fs::canonicalize(resources)?);
    let specification: ResourceSet = serde_json::from_str(include_str!(
        "../../../resources/desktop-dictionary.lock.json"
    ))?;
    let state_root = std::path::absolute(state_root)?;
    verify_resources_once(&resources, &specification, &state_root)?;
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
        phrase_preedit: None,
        clipboard_history_path: None,
        online_provider_socket: None,
        translation_provider_socket: None,
        cloud_dictionary_provider_socket: None,
        cloud_clipboard_provider_socket: None,
        voice_provider_socket: None,
        // Written only when a model has actually been installed as its own artifact; a host that
        // places one beside the dictionaries needs no configuration.
        sentence_model: None,
        settled_model: settled_model_beside(&resources),
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
            // Which row the user reached for, read before dispatching because the view it is
            // relative to is gone afterwards. Every platform host routes candidate selection
            // through here, so counting it here covers all of them without a line of platform
            // code; doing it per host would have meant six chances to forget.
            let position = selected_position(session, &action);
            let result = session
                .runtime
                .dispatch(action)
                .map_err(|e| e.to_string())?;
            if result.commit.is_some() {
                if let Some(position) = position {
                    record_selection(session, position);
                }
            }
            let result = session.complete_transition(result);
            serde_json::to_value(result).map_err(|e| e.to_string())
        })
    })
}

/// The one-based position of the candidate an action is about, or `None` when it is not about one.
///
/// `Select` indexes into the visible page, so the page it sits on has to be added back; a commit
/// from row 2 of page 3 is the twentieth candidate, and counting it as the second would make the
/// first-candidate rate look far better than it is. `SelectAnyCandidate` already carries an index
/// into the whole list.
fn selected_position(session: &HostSession, action: &Action) -> Option<usize> {
    match action {
        Action::Select(id) => {
            let view = session.runtime.view();
            Some(view.page * view.page_size + id.index + 1)
        }
        Action::SelectAnyCandidate(id) => Some(id.index + 1),
        _ => None,
    }
}

/// Count a commit against the position it came from, in the store the host already keeps.
///
/// Best effort on purpose: statistics must never be the reason a keystroke fails, so a locked or
/// unwritable store is dropped rather than surfaced. The store honours the user's switch itself,
/// so there is no second check here to fall out of step with it.
fn record_selection(session: &HostSession, position: usize) {
    let directory = std::path::Path::new(&session.options.user_data);
    if !directory.is_absolute() {
        return;
    }
    let _ = TypingStatisticsStore::new(directory).record_selection(position);
}

#[cfg(test)]
mod tests;

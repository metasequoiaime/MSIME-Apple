//! Versioned, thread-confined C interface for native IME hosts.
//! A handle registry rejects stale and wrong-thread handles without dereferencing them.

use msime_client_core::dictionary_access::DictionaryAccess;
use msime_client_core::preferences::{
    InputScheme, Preferences, PreferencesSnapshot, PreferencesStore, ShuangpinProfile,
};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_engine_bridge::{CandidateEdge, Command, EngineOptions, Session};
use msime_input_runtime::{Action, CandidateId, OnlineQuery, Runtime, Transition};
#[cfg(unix)]
use msime_input_runtime::UnixSocketProvider;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
mod dictionary;
pub use dictionary::{dictionary_request_json, msime_client_dictionary};

thread_local! {
    static SESSIONS: RefCell<HashMap<u64, HostSession>> = RefCell::new(HashMap::new());
}

struct HostSession {
    runtime: Runtime,
    options: EngineOptions,
    applied: Preferences,
    requested: Option<PreferencesSnapshot>,
    punctuation_override: Option<bool>,
    page_size_override: Option<u8>,
    // Declared last so the Engine/runtime is dropped before releasing access.
    _dictionary_access: DictionaryAccess,
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
        options.local_unicode = snapshot.preferences.local_modes.unicode;
        options.local_date_time = snapshot.preferences.local_modes.date_time;
        options.local_quick_phrase = snapshot.preferences.local_modes.quick_phrase;
        options.local_emoji = snapshot.preferences.local_modes.emoji;
        options.local_kaomoji = snapshot.preferences.local_modes.kaomoji;
        options.local_super_jianpin = snapshot.preferences.local_modes.super_jianpin;
        options.local_temporary_english = snapshot.preferences.local_modes.temporary_english;
        options.local_temporary_japanese = snapshot.preferences.local_modes.temporary_japanese;
        let helpcode = snapshot.preferences.active_helpcode();
        options.helpcode = helpcode.enabled;
        options.helpcode_schema = helpcode.schema.as_str().into();
        options.chinese_punctuation = snapshot.preferences.chinese_punctuation;
        // Build and validate first; errors leave the original session usable.
        let mut engine = Session::new(&options).map_err(|e| e.to_string())?;
        if let Some(enabled) = self.punctuation_override {
            engine
                .set_chinese_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
        }
        self.runtime
            .replace_engine(
                engine,
                self.page_size_override
                    .unwrap_or(snapshot.preferences.candidate_page_size),
            )
            .map_err(|e| e.to_string())?;
        self.options = options;
        self.applied = snapshot.preferences.clone();
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
            json!({ "revision": snapshot.revision, "deferred": snapshot.preferences != self.applied, "view": self.runtime.view() }),
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
        let options = options.into_engine_options();
        let dictionary_access = DictionaryAccess::try_session(
            std::path::Path::new(&options.user_data),
            std::path::Path::new(&options.dictionaries),
        )
        .map_err(|_| "dictionary access unavailable")?
        .ok_or("dictionary maintenance busy")?;
        let engine = Session::new(&options).map_err(|e| e.to_string())?;
        let runtime = Runtime::new(engine, page_size).map_err(|e| e.to_string())?;
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
                    page_size_override: None,
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
            serde_json::to_value(session.runtime.online_query().map_err(|e| e.to_string())?)
                .map_err(|e| e.to_string())
        })
    })
}

/// Query a user-owned Unix-socket provider off the session thread.
/// Returns null when the provider has no candidate or is unavailable.
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
        let path = std::str::from_utf8(unsafe {
            std::slice::from_raw_parts(socket_path, socket_length)
        })
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

/// Apply a provider result returned for a previously copied OnlineQuery.
/// The query and candidate buffers are UTF-8 and are never retained.
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
        if query.is_null() || candidate.is_null() || query_length > 16384 || candidate_length > 4096 {
            return Err("invalid online candidate buffer".into());
        }
        let query = serde_json::from_slice::<OnlineQuery>(unsafe {
            std::slice::from_raw_parts(query, query_length)
        })
        .map_err(|_| "invalid online query document")?;
        let candidate = std::str::from_utf8(unsafe {
            std::slice::from_raw_parts(candidate, candidate_length)
        })
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
    fn sessions_hold_access_until_destroy_and_failed_edits_release_it() {
        let dir = tempfile::tempdir().unwrap();
        let first = test_host(dir.path());
        let second = test_host(dir.path());
        let user = dir.path().join("user");
        let dictionaries = dir.path().join("dictionaries");
        assert!(DictionaryAccess::try_maintenance(&user, &dictionaries)
            .unwrap()
            .is_none());
        read(msime_client_destroy(first));
        assert!(DictionaryAccess::try_maintenance(&user, &dictionaries)
            .unwrap()
            .is_none());
        read(msime_client_destroy(second));
        let writer = DictionaryAccess::try_maintenance(&user, &dictionaries)
            .unwrap()
            .unwrap();
        let options = json!({ "api_version": 1, "resources": dir.path().join("resources"), "user_data": user, "cache": dir.path().join("cache"), "dictionaries": dictionaries, "preferences": Preferences::default() }).to_string();
        assert_eq!(
            read(unsafe { msime_client_create(options.as_ptr(), options.len()) })["error"],
            "dictionary maintenance busy"
        );
        drop(writer);
        let handle = test_host(dir.path());
        let engine_options = SESSIONS.with(|sessions| sessions.borrow()[&handle].options.clone());
        assert_eq!(
            edit_personal_dictionary(&engine_options, None, None, "fixture"),
            Err("dictionary maintenance busy")
        );
        read(msime_client_destroy(handle));
        assert_eq!(
            edit_personal_dictionary(&engine_options, None, None, ""),
            Err("dictionary request id required")
        );
        assert_eq!(
            edit_personal_dictionary(&engine_options, None, None, "fixture"),
            Err("dictionary edit rejected")
        );
        assert!(DictionaryAccess::try_maintenance(&user, &dictionaries)
            .unwrap()
            .is_some());
    }
    #[test]
    fn native_page_size_defers_and_survives_preference_rebuild() {
        let dir = tempfile::tempdir().unwrap();
        let handle = test_host(dir.path());
        read(msime_client_focus(handle, true));
        let first = read(msime_client_set_candidate_page_size(handle, 5));
        assert_eq!(first["value"]["deferred"], false);
        read(msime_client_character(handle, b'U', true));
        for byte in b"4e2d" {
            read(msime_client_character(handle, *byte, false));
        }
        let before = read(msime_client_view(handle))["value"].clone();
        for size in [7, 9] {
            let pending = read(msime_client_set_candidate_page_size(handle, size));
            assert_eq!(pending["value"]["deferred"], true);
            assert_eq!(pending["value"]["view"], before);
        }
        for size in [0, 10, 255] {
            assert_eq!(
                read(msime_client_set_candidate_page_size(handle, size))["ok"],
                false
            );
            assert_eq!(read(msime_client_view(handle))["value"], before);
        }
        let committed = read(msime_client_command(handle, 1));
        assert_eq!(committed["value"]["commit"], "中");
        assert_eq!(
            committed["value"]["commit_context"]["local_mode"],
            "unicode"
        );
        assert_eq!(committed["value"]["view"]["local_mode"], "none");
        assert_eq!(committed["value"]["view"]["page_size"], 9);
        let preferences = Preferences {
            candidate_page_size: 2,
            ..Preferences::default()
        };
        let updated = update(handle, 1, &preferences);
        assert_eq!(updated["value"]["deferred"], false);
        assert_eq!(updated["value"]["view"]["page_size"], 9);
        let unchanged = read(msime_client_view(handle));
        read(msime_client_set_candidate_page_size(handle, 9));
        assert_eq!(read(msime_client_view(handle)), unchanged);
        assert_eq!(
            std::thread::spawn(
                move || read(msime_client_set_candidate_page_size(handle, 5))["ok"].clone()
            )
            .join()
            .unwrap(),
            false
        );
        read(msime_client_destroy(handle));
        assert_eq!(
            read(msime_client_set_candidate_page_size(handle, 5))["ok"],
            false
        );
    }
    #[test]
    fn page_edge_commands_keep_engine_composition() {
        let dir = tempfile::tempdir().unwrap();
        let handle = test_host(dir.path());
        read(msime_client_focus(handle, true));
        read(msime_client_character(handle, b'U', true));
        for byte in b"4e2d" {
            read(msime_client_character(handle, *byte, false));
        }
        let before = read(msime_client_view(handle))["value"].clone();
        assert!(!before["candidates"].as_array().unwrap().is_empty());
        for command in [105, 104] {
            let moved = read(msime_client_command(handle, command));
            assert_eq!(moved["ok"], true);
            assert_eq!(moved["value"]["handled"], true);
            assert!(moved["value"]["commit"].is_null());
            assert_eq!(
                moved["value"]["view"]["editing_text"],
                before["editing_text"]
            );
            assert_eq!(
                moved["value"]["view"]["caret_position"],
                before["caret_position"]
            );
        }
        assert_eq!(
            read(msime_client_command(handle, 1))["value"]["commit"],
            "中"
        );
        read(msime_client_destroy(handle));
    }
    #[test]
    fn local_mode_disable_is_deferred_and_preserves_other_modes() {
        let dir = tempfile::tempdir().unwrap();
        let handle = test_host(dir.path());
        read(msime_client_focus(handle, true));
        read(msime_client_character(handle, b'U', true));
        let before = read(msime_client_view(handle));
        let mut preferences = Preferences::default();
        preferences.local_modes.unicode = false;
        assert_eq!(update(handle, 1, &preferences)["value"]["deferred"], true);
        assert_eq!(read(msime_client_view(handle)), before);
        SESSIONS.with(|sessions| assert!(sessions.borrow()[&handle].options.local_unicode));
        read(msime_client_command(handle, 3));
        SESSIONS.with(|sessions| {
            let sessions = sessions.borrow();
            assert!(!sessions[&handle].options.local_unicode);
            assert!(sessions[&handle].options.local_emoji);
        });
        read(msime_client_destroy(handle));
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
            ..chinese.clone()
        };
        assert_eq!(update(handle, 1, &japanese)["value"]["deferred"], true);
        let committed = read(msime_client_command(handle, 2));
        assert_eq!(committed["value"]["commit"], "b;");
        assert_eq!(committed["value"]["commit_context"]["scheme"], 1);
        assert_eq!(committed["value"]["view"]["scheme"], 3);
        let kana = read(msime_client_character(handle, b'a', false));
        assert_eq!(kana["ok"], true);
        assert_eq!(kana["value"]["view"]["preedit"], "a");
        assert_eq!(kana["value"]["view"]["scheme"], 3);
        assert_eq!(kana["value"]["view"]["candidates"][0]["text"], "あ");
        assert_eq!(kana["value"]["view"]["candidates"][1]["text"], "ア");
        assert_eq!(update(handle, 2, &chinese)["value"]["deferred"], true);
        read(msime_client_command(handle, 3));
        read(msime_client_character(handle, b'b', false));
        assert_eq!(
            read(msime_client_character(handle, b';', false))["value"]["view"]["editing_text"],
            "b;"
        );
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
            },
            shuangpin_helpcode: HelpcodePreferences {
                enabled: true,
                schema: HelpcodeSchema::Shouyou2,
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
}

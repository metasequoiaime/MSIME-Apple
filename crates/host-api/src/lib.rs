//! Versioned, thread-confined C interface for native IME hosts.
//! A handle registry rejects stale and wrong-thread handles without dereferencing them.

use msime_client_core::preferences::{InputScheme, Preferences, PreferencesStore};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_engine_bridge::{Command, EngineOptions, Session};
use msime_input_runtime::{Action, CandidateId, Runtime};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

thread_local! {
    static SESSIONS: RefCell<HashMap<u64, Runtime>> = RefCell::new(HashMap::new());
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
    })?)
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
    action: impl FnOnce(&mut Runtime) -> Result<Value, String>,
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
        with_session(handle, |runtime| {
            let result = runtime.dispatch(action).map_err(|e| e.to_string())?;
            serde_json::to_value(result).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_abi_version() -> u32 {
    1
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
        let options = EngineOptions {
            resources: options.resources,
            user_data: options.user_data,
            cache: options.cache,
            dictionaries: options.dictionaries,
            scheme: match options.preferences.scheme {
                InputScheme::Quanpin => 0,
                InputScheme::Shuangpin => 1,
                InputScheme::Wubi => 2,
                InputScheme::Japanese => 3,
            },
            learning: options.preferences.learning,
            chinese_punctuation: options.preferences.chinese_punctuation,
        };
        let engine = Session::new(&options).map_err(|e| e.to_string())?;
        let runtime = Runtime::new(engine, page_size).map_err(|e| e.to_string())?;
        let view = runtime.view();
        let output = serde_json::to_value(&view).map_err(|e| e.to_string())?;
        SESSIONS.with(|sessions| sessions.borrow_mut().insert(view.session, runtime));
        Ok(output)
    })
}

#[no_mangle]
pub extern "C" fn msime_client_focus(handle: u64, focused: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |runtime| {
            let result = runtime.focus(focused).map_err(|e| e.to_string())?;
            serde_json::to_value(result).map_err(|e| e.to_string())
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
        _ => return response(|| Err("unknown input command".into())),
    };
    dispatch(handle, action)
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
        with_session(handle, |runtime| {
            serde_json::to_value(runtime.view()).map_err(|e| e.to_string())
        })
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
    fn read(pointer: *mut c_char) -> Value {
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
        assert_eq!(read(msime_client_destroy(handle))["ok"], true);
        assert_eq!(read(msime_client_view(handle))["ok"], false);
        assert_eq!(read(msime_client_destroy(handle))["ok"], false);
    }
    #[test]
    fn invalid_buffers_and_commands_return_owned_errors() {
        assert_eq!(
            read(unsafe { msime_client_create(std::ptr::null(), 0) })["ok"],
            false
        );
        assert_eq!(read(msime_client_command(0, 999))["ok"], false);
        unsafe { msime_client_string_free(std::ptr::null_mut()) };
    }
}

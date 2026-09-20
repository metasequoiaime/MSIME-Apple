//! Host configuration, preferences, the skin catalog and clipboard history.
//!
//! Part of the C ABI; see the parent module for what these shims guarantee.

use crate::*;

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

/// The shared preference defaults, as the document a host would have to produce.
///
/// A host that patches one key into a nested preference object needs the rest of
/// that object's fields, because the nested structures require all of them - only
/// the object as a whole is optional. Writing those defaults into a platform host
/// would put a second copy of this contract in another language, so they are
/// published here instead.
#[no_mangle]
pub extern "C" fn msime_client_default_preferences() -> *mut c_char {
    response(|| {
        serde_json::to_value(msime_client_core::preferences::Preferences::default())
            .map_err(|e| e.to_string())
    })
}

/// Per-key double-pinyin hint text for one profile, read out of the Engine's own
/// profile tables.
///
/// A touch keyboard labels its letter keys with the units they carry, and a face
/// that keeps its own copy of that keymap drifts from the scheme the session
/// actually runs. The hints depend only on the profile, not on session state, so
/// this takes no handle. An unknown name yields an empty object rather than the
/// default profile's hints: labelling the keys with a scheme the session is not
/// running is worse than labelling nothing.
/// # Safety
/// `profile` points to `length` readable UTF-8 bytes. Null is rejected.
/// The returned response must be released with `msime_client_string_free`.
#[no_mangle]
pub unsafe extern "C" fn msime_client_shuangpin_key_hints(
    profile: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if profile.is_null() || length > 64 {
            return Err("invalid shuangpin profile buffer".into());
        }
        // SAFETY: guaranteed by the documented caller contract; size checked above.
        let bytes = unsafe { std::slice::from_raw_parts(profile, length) };
        let name = std::str::from_utf8(bytes).map_err(|_| "invalid shuangpin profile encoding")?;
        let hints: serde_json::Map<String, serde_json::Value> =
            msime_engine_bridge::shuangpin_key_hints(name)
                .into_iter()
                .map(|entry| (entry.key, serde_json::Value::String(entry.hint)))
                .collect();
        Ok(serde_json::Value::Object(hints))
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
            /// Local hour of the commit, 0-23. Absent from hosts that have not been taught to
            /// send one, whose days then have characters but no hourly breakdown - which is the
            /// honest result, since this layer cannot resolve the host's timezone itself.
            #[serde(default)]
            hour: Option<u8>,
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
            StatisticsAction::Record {
                text,
                source,
                day,
                hour,
            } => {
                let recorded = store
                    .record(&text, source, &day, hour)
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

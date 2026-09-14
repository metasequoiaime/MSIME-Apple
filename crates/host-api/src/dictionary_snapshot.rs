//! Native-only snapshot preparation. Staged paths stay private until a future
//! activation transaction can own publication and session coordination.
use super::{response, DictionaryAccess, HostOptions};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_engine_bridge::{
    dictionary_state_revision, stage_dictionary_state, EngineOptions, SnapshotReadError,
};
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    collections::HashMap,
    ffi::{c_char, c_void},
    io::Write,
    path::Path,
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
};

mod record;

const BUFFER_LIMIT: usize = 65536;
const HANDLE_LIMIT: usize = 8;
const ACTIVATION_RECEIPT_NAME: &str = ".msime-snapshot-activation";
static NEXT: AtomicU64 = AtomicU64::new(1);
static PREPARED: OnceLock<Mutex<HashMap<u64, Prepared>>> = OnceLock::new();
fn registry() -> &'static Mutex<HashMap<u64, Prepared>> {
    PREPARED.get_or_init(Default::default)
}

struct Prepared {
    directory: tempfile::TempDir,
    active_options: EngineOptions,
    options: EngineOptions,
    source_version: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PrepareRequest {
    options: HostOptions,
    staging_root: String,
    expected_version: String,
    records: usize,
    #[serde(default)]
    activation_id: Option<String>,
}

/// Called synchronously: positive UTF-8 JSON length, zero only at verified EOF,
/// negative for cancellation/corruption. It must not throw, unwind or retain buffer.
pub type SnapshotNext = unsafe extern "C" fn(*mut c_void, *mut u8, usize) -> isize;

fn parse_options(bytes: &[u8]) -> Result<EngineOptions, &'static str> {
    if bytes.len() > BUFFER_LIMIT {
        return Err("invalid snapshot options");
    }
    let options: HostOptions =
        serde_json::from_slice(bytes).map_err(|_| "invalid snapshot options")?;
    validate_options(options)
}
fn validate_options(options: HostOptions) -> Result<EngineOptions, &'static str> {
    if options.api_version != 1 || options.preferences.validate().is_err() {
        return Err("invalid snapshot options");
    }
    Ok(options.into_engine_options())
}

fn version(options: &EngineOptions) -> Result<String, &'static str> {
    let _access = DictionaryAccess::try_session(
        Path::new(&options.user_data),
        Path::new(&options.dictionaries),
    )
    .map_err(|_| "snapshot access unavailable")?
    .ok_or("snapshot access busy")?;
    let mut hash = Sha256::new();
    hash.update(b"msime-host-dictionary-version-v1");
    for path in [
        &options.resources,
        &options.user_data,
        &options.cache,
        &options.dictionaries,
    ] {
        if !Path::new(path).is_absolute() {
            return Err("invalid snapshot path");
        }
        let canonical = Path::new(path)
            .canonicalize()
            .map_err(|_| "snapshot path unavailable")?;
        let text = canonical.to_str().ok_or("invalid snapshot path")?;
        hash.update((text.len() as u64).to_be_bytes());
        hash.update(text.as_bytes());
    }
    hash.update(dictionary_state_revision(options).map_err(|_| "snapshot revision unavailable")?);
    Ok(format!("{:x}", hash.finalize()))
}

fn valid_activation_id(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() == 36
        && [8, 13, 18, 23].iter().all(|&index| bytes[index] == b'-')
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| [8, 13, 18, 23].contains(&index) || byte.is_ascii_hexdigit())
}

fn activation_receipt(options: &EngineOptions) -> Result<Option<String>, &'static str> {
    let path = Path::new(&options.user_data).join(ACTIVATION_RECEIPT_NAME);
    let value = match std::fs::read(path) {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err("snapshot activation receipt unavailable"),
    };
    let value = std::str::from_utf8(&value).map_err(|_| "invalid snapshot activation receipt")?;
    if !valid_activation_id(value) {
        return Err("invalid snapshot activation receipt");
    }
    Ok(Some(value.to_owned()))
}

fn write_activation_receipt(
    options: &EngineOptions,
    activation_id: &str,
) -> Result<(), &'static str> {
    let directory = Path::new(&options.user_data);
    let temporary = directory.join(format!("{ACTIVATION_RECEIPT_NAME}.tmp"));
    let path = directory.join(ACTIVATION_RECEIPT_NAME);
    let mut file = std::fs::OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&temporary)
        .map_err(|_| "snapshot activation receipt unavailable")?;
    file.write_all(activation_id.as_bytes())
        .and_then(|_| file.sync_all())
        .map_err(|_| "snapshot activation receipt unavailable")?;
    std::fs::rename(temporary, path).map_err(|_| "snapshot activation receipt unavailable")
}

fn prepare(
    request: PrepareRequest,
    specification: &ResourceSet,
    stream: impl Iterator<Item = Result<msime_engine_bridge::DictionaryStateRecord, SnapshotReadError>>
        + 'static,
) -> Result<Prepared, &'static str> {
    if request.records > 500_000 || request.expected_version.len() != 64 {
        return Err("invalid snapshot bounds");
    }
    if request
        .activation_id
        .as_deref()
        .is_some_and(|value| !valid_activation_id(value))
    {
        return Err("invalid snapshot activation id");
    }
    let options = validate_options(request.options)?;
    let current = version(&options)?;
    if current != request.expected_version {
        return Err("snapshot source changed");
    }
    let root = Path::new(&request.staging_root);
    if !root.is_absolute() {
        return Err("invalid snapshot staging root");
    }
    let root = root
        .canonicalize()
        .map_err(|_| "snapshot staging root unavailable")?;
    for path in [
        &options.resources,
        &options.user_data,
        &options.cache,
        &options.dictionaries,
    ] {
        let path = Path::new(path)
            .canonicalize()
            .map_err(|_| "snapshot path unavailable")?;
        if root.starts_with(&path) || path.starts_with(&root) {
            return Err("snapshot staging overlaps active paths");
        }
    }
    ResourceStore::new(&options.resources)
        .verify(Path::new(&options.resources), specification)
        .map_err(|_| "snapshot resources rejected")?;
    let content_id = specification
        .generation()
        .map_err(|_| "snapshot resources rejected")?;
    let directory = tempfile::Builder::new()
        .prefix("snapshot-")
        .tempdir_in(root)
        .map_err(|_| "snapshot staging unavailable")?;
    let generation = directory.path().join("generation");
    let mut count = 0;
    let expected = request.records;
    let mut source = stream;
    let checked = std::iter::from_fn(move || match source.next() {
        Some(Ok(record)) if count < expected => {
            count += 1;
            Some(Ok(record))
        }
        Some(_) => Some(Err(SnapshotReadError)),
        None if count == expected => None,
        None => Some(Err(SnapshotReadError)),
    });
    let staged = stage_dictionary_state(
        &options,
        generation.to_str().ok_or("invalid snapshot path")?,
        &content_id,
        expected.max(1),
        checked,
    )
    .map_err(|_| "snapshot preparation rejected")?;
    if let Some(activation_id) = request.activation_id.as_deref() {
        write_activation_receipt(&staged, activation_id)?;
    }
    // Learning may continue during expensive preparation. Reject a changed preview.
    if version(&options)? != current {
        return Err("snapshot source changed");
    }
    Ok(Prepared {
        directory,
        active_options: options,
        options: staged,
        source_version: current,
    })
}

fn activate(handle: u64, expected: &str) -> Result<Value, &'static str> {
    let mut entries = registry()
        .lock()
        .map_err(|_| "snapshot registry unavailable")?;
    let prepared = entries.get(&handle).ok_or("unknown snapshot handle")?;
    if prepared.source_version != expected {
        return Err("snapshot source changed");
    }
    let active = &prepared.active_options;
    let staged = &prepared.options;
    let _access = DictionaryAccess::try_maintenance(
        Path::new(&active.user_data),
        Path::new(&active.dictionaries),
    )
    .map_err(|_| "snapshot access unavailable")?
    .ok_or("snapshot access busy")?;
    if version_without_access(active)? != expected {
        return Err("snapshot source changed");
    }
    let suffix = format!(".msime-snapshot-old-{handle}");
    let pairs = [
        (&active.user_data, &staged.user_data),
        (&active.cache, &staged.cache),
        (&active.dictionaries, &staged.dictionaries),
    ];
    let mut moved = Vec::new();
    let rollback = |moved: &[(std::path::PathBuf, std::path::PathBuf, std::path::PathBuf)]| {
        for (old, saved, replacement) in moved.iter().rev() {
            let _ = std::fs::rename(old, replacement);
            let _ = std::fs::rename(saved, old);
        }
    };
    for (current, replacement) in pairs {
        let current = Path::new(current);
        let replacement = Path::new(replacement);
        // Engine's production layout stores dictionaries under user_data. A
        // matching subtree is already swapped with its parent; moving it again
        // would fail because the staged subtree no longer exists.
        if pairs.iter().any(|(parent, staged_parent)| {
            let parent = Path::new(parent);
            current != parent
                && current.strip_prefix(parent).ok().is_some_and(|relative| {
                    replacement.strip_prefix(staged_parent).ok() == Some(relative)
                })
        }) {
            continue;
        }
        let backup = current.with_file_name(format!(
            "{}{}",
            current
                .file_name()
                .and_then(|x| x.to_str())
                .unwrap_or("state"),
            suffix
        ));
        if std::fs::rename(current, &backup).is_err() {
            rollback(&moved);
            return Err("snapshot activation failed");
        }
        if std::fs::rename(replacement, current).is_err() {
            let _ = std::fs::rename(&backup, current);
            rollback(&moved);
            return Err("snapshot activation failed");
        }
        moved.push((current.to_path_buf(), backup, replacement.to_path_buf()));
    }
    for (_, backup, _) in moved {
        let _ = std::fs::remove_dir_all(backup);
    }
    entries.remove(&handle);
    Ok(json!({"activated": true}))
}

fn version_without_access(options: &EngineOptions) -> Result<String, &'static str> {
    let mut hash = Sha256::new();
    hash.update(b"msime-host-dictionary-version-v1");
    for path in [
        &options.resources,
        &options.user_data,
        &options.cache,
        &options.dictionaries,
    ] {
        let canonical = Path::new(path)
            .canonicalize()
            .map_err(|_| "snapshot path unavailable")?;
        let text = canonical.to_str().ok_or("invalid snapshot path")?;
        hash.update((text.len() as u64).to_be_bytes());
        hash.update(text.as_bytes());
    }
    hash.update(dictionary_state_revision(options).map_err(|_| "snapshot revision unavailable")?);
    Ok(format!("{:x}", hash.finalize()))
}

fn register(prepared: Prepared) -> Result<Value, &'static str> {
    let mut entries = registry()
        .lock()
        .map_err(|_| "snapshot registry unavailable")?;
    if entries.len() >= HANDLE_LIMIT {
        return Err("too many prepared snapshots");
    }
    let handle = NEXT
        .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |n| n.checked_add(1))
        .map_err(|_| "snapshot handle unavailable")?;
    let output = json!({"handle": handle, "source_version": prepared.source_version});
    entries.insert(handle, prepared);
    Ok(output)
}

/// Read a preview version binding canonical paths and the consistent Engine journal.
/// # Safety
/// `options` points to `length` readable bytes. Trusted native paths only.
#[no_mangle]
pub unsafe extern "C" fn msime_client_snapshot_version(
    options: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if options.is_null() || length > BUFFER_LIMIT {
            return Err("invalid snapshot buffer".into());
        }
        let options = parse_options(unsafe { std::slice::from_raw_parts(options, length) })?;
        let version = version(&options)?;
        let generation = activation_receipt(&options)?.unwrap_or_else(|| "legacy".to_owned());
        Ok(json!({"version": version, "generation": generation}))
    })
}

/// Prepare from a native callback; holds no registry lock while calling the host.
/// # Safety
/// Request/context remain valid for this synchronous call. The callback obeys
/// SnapshotNext, writes at most capacity bytes, and does not unwind or retain buffer.
#[no_mangle]
pub unsafe extern "C" fn msime_client_snapshot_prepare(
    request: *const u8,
    length: usize,
    next: Option<SnapshotNext>,
    context: *mut c_void,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > BUFFER_LIMIT {
            return Err("invalid snapshot buffer".into());
        }
        let next = next.ok_or("missing snapshot reader")?;
        let request: PrepareRequest =
            serde_json::from_slice(unsafe { std::slice::from_raw_parts(request, length) })
                .map_err(|_| "invalid snapshot request")?;
        let specification: ResourceSet = serde_json::from_str(include_str!(
            "../../../resources/desktop-dictionary.lock.json"
        ))
        .map_err(|_| "snapshot resources rejected")?;
        let mut buffer = vec![0; BUFFER_LIMIT];
        let stream = std::iter::from_fn(move || {
            let length = unsafe { next(context, buffer.as_mut_ptr(), buffer.len()) };
            if length == 0 {
                return None;
            }
            if length < 0 || length as usize > buffer.len() {
                return Some(Err(SnapshotReadError));
            }
            Some(record::decode(&buffer[..length as usize]))
        });
        let prepared = prepare(request, &specification, stream)?;
        register(prepared).map_err(Into::into)
    })
}

/// Discard only a process-owned, unpublished preparation. Unknown/consumed IDs fail.
#[no_mangle]
pub extern "C" fn msime_client_snapshot_discard(handle: u64) -> *mut c_char {
    response(|| {
        let mut entries = registry()
            .lock()
            .map_err(|_| "snapshot registry unavailable")?;
        let prepared = entries.get(&handle).ok_or("unknown snapshot handle")?;
        let _access = DictionaryAccess::try_maintenance(
            Path::new(&prepared.options.user_data),
            Path::new(&prepared.options.dictionaries),
        )
        .map_err(|_| "snapshot access unavailable")?
        .ok_or("snapshot access busy")?;
        std::fs::remove_dir_all(prepared.directory.path())
            .map_err(|_| "snapshot cleanup failed")?;
        entries.remove(&handle);
        Ok(json!({"discarded": true}))
    })
}

#[no_mangle]
pub extern "C" fn msime_client_snapshot_activate(
    handle: u64,
    expected: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if expected.is_null() || length != 64 {
            return Err("invalid snapshot version".into());
        }
        let expected = std::str::from_utf8(unsafe { std::slice::from_raw_parts(expected, length) })
            .map_err(|_| "invalid snapshot version")?;
        activate(handle, expected).map_err(Into::into)
    })
}

#[cfg(test)]
mod tests;

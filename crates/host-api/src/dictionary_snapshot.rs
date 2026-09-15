//! Native-only snapshot preparation. Staged paths stay private until a future
//! activation transaction can own publication and session coordination.
use super::{response, DictionaryAccess, HostOptions};
use msime_client_core::resources::{ResourceSet, ResourceStore};
use msime_engine_bridge::{
    dictionary_state_revision, stage_dictionary_state, EngineOptions, Session, SnapshotReadError,
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
// The guard's own file, which stays put while everything around it is swapped.
const DICTIONARY_ACCESS_LOCK_NAME: &str = ".msime-dictionary-access.lock";
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
    // Construct the replacement engine while the current generation is still
    // untouched.  A malformed or otherwise unusable generation must not make
    // the active dictionaries unavailable after publication.
    let replacement_session = Session::new(staged).map_err(|_| "snapshot engine unavailable")?;
    // Windows cannot rename SQLite files while the probe keeps them open.
    drop(replacement_session);
    let suffix = format!(".msime-snapshot-old-{handle}");
    let pairs = [
        (&active.user_data, &staged.user_data),
        (&active.cache, &staged.cache),
        (&active.dictionaries, &staged.dictionaries),
    ];
    let backups: Vec<std::path::PathBuf> = pairs
        .iter()
        .map(|(current, _)| {
            let current = Path::new(current.as_str());
            current.with_file_name(format!(
                "{}{}",
                current
                    .file_name()
                    .and_then(|x| x.to_str())
                    .unwrap_or("state"),
                suffix
            ))
        })
        .collect();
    // Swap each root's contents rather than the root itself.
    //
    // Renaming the roots cannot work on Windows: the maintenance guard holds
    // an open handle on a lock file inside them, and Windows refuses to rename
    // a directory containing any open handle - share mode does not help. So
    // activation has never succeeded there. Moving the entries leaves the lock
    // files exactly where they are, which is also what they are documented to
    // require: they are stable coordination objects, and renaming a root moved
    // one out from under every other process using it.
    let roots: Vec<&Path> = pairs
        .iter()
        .map(|(current, _)| Path::new(current.as_str()))
        .collect();
    let staged_roots: Vec<&Path> = pairs
        .iter()
        .map(|(_, replacement)| Path::new(replacement.as_str()))
        .collect();
    let mut moved: Vec<(std::path::PathBuf, std::path::PathBuf)> = Vec::new();
    let rollback = |moved: &[(std::path::PathBuf, std::path::PathBuf)]| {
        for (from, to) in moved.iter().rev() {
            let _ = std::fs::rename(to, from);
        }
        for backup in &backups {
            let _ = std::fs::remove_dir_all(backup);
        }
    };
    // An entry that leads to another root nested below this one is left alone:
    // that root does its own swap, and it holds its own lock file.
    let leads_to_nested_root = |root: &Path, entry: &Path, all: &[&Path]| {
        all.iter()
            .any(|other| *other != root && other.starts_with(entry))
    };
    for (index, (current, replacement)) in pairs.iter().enumerate() {
        let current = Path::new(current.as_str());
        let replacement = Path::new(replacement.as_str());
        let backup = &backups[index];
        if std::fs::create_dir_all(backup).is_err() {
            rollback(&moved);
            return Err("snapshot activation failed");
        }
        // Out with the old.
        let listing = match std::fs::read_dir(current) {
            Ok(listing) => listing,
            Err(_) => {
                rollback(&moved);
                return Err("snapshot activation failed");
            }
        };
        for entry in listing {
            let Ok(entry) = entry else {
                rollback(&moved);
                return Err("snapshot activation failed");
            };
            let path = entry.path();
            if entry.file_name() == DICTIONARY_ACCESS_LOCK_NAME
                || leads_to_nested_root(roots[index], &path, &roots)
            {
                continue;
            }
            let destination = backup.join(entry.file_name());
            if std::fs::rename(&path, &destination).is_err() {
                rollback(&moved);
                return Err("snapshot activation failed");
            }
            moved.push((path, destination));
        }
        // In with the new.
        let listing = match std::fs::read_dir(replacement) {
            Ok(listing) => listing,
            Err(_) => {
                rollback(&moved);
                return Err("snapshot activation failed");
            }
        };
        for entry in listing {
            let Ok(entry) = entry else {
                rollback(&moved);
                return Err("snapshot activation failed");
            };
            let path = entry.path();
            if entry.file_name() == DICTIONARY_ACCESS_LOCK_NAME
                || leads_to_nested_root(staged_roots[index], &path, &staged_roots)
            {
                continue;
            }
            let destination = current.join(entry.file_name());
            if std::fs::rename(&path, &destination).is_err() {
                rollback(&moved);
                return Err("snapshot activation failed");
            }
            moved.push((path, destination));
        }
    }
    for backup in &backups {
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
fn discard(handle: u64) -> Result<Value, &'static str> {
    let mut entries = registry()
        .lock()
        .map_err(|_| "snapshot registry unavailable")?;
    let prepared = entries.get(&handle).ok_or("unknown snapshot handle")?;
    // A prepared directory is outside all active roots (validated by prepare),
    // so cleaning it never touches the live journal or dictionaries. Requiring
    // the maintenance lock here made cancellation fail while an input session
    // held its normal shared lock, leaking the process-owned handle.
    std::fs::remove_dir_all(prepared.directory.path()).map_err(|_| "snapshot cleanup failed")?;
    entries.remove(&handle);
    Ok(json!({"discarded": true}))
}

#[no_mangle]
pub extern "C" fn msime_client_snapshot_discard(handle: u64) -> *mut c_char {
    response(|| discard(handle).map_err(Into::into))
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

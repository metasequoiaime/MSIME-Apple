//! Relocation of the Linux user-data root.
//!
//! On Linux the default state root (`$XDG_CONFIG_HOME/msime-client`) is also where every consumer finds its locator: the IBus launcher, the Fcitx5 addon, the clipboard monitor unit and the settings launcher all read `runtime-options.json` from that fixed path, and the provider services read their credential files from the same directory. A move therefore never relocates that directory itself. It moves the state entries (dictionaries, learning data, cache, preferences, skins, clipboard history) into the chosen directory and rewrites the path-bearing values of the locators in place, keeping every other key (provider sockets, models) the setup wrote.

use crate::linux_process;
use crate::{HostActionError, RuntimeOptionsState};
use serde_json::Value;
use std::collections::BTreeSet;
use std::ffi::OsString;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

pub(crate) const DATA_DIRECTORY_MARKER: &str = ".metasequoiaime-data";
const OPTIONS_FILE: &str = "runtime-options.json";
/// Files that belong to the fixed configuration directory rather than to the movable state: the locator and the provider credentials the systemd services read from `$XDG_CONFIG_HOME/msime-client`.
const PINNED_FILES: [&str; 4] = [
    OPTIONS_FILE,
    "ai-provider.json",
    "tencent-provider.json",
    "voice-provider.json",
];
const STAGING_PREFIX: &str = ".msime-data-migration-";
/// The picker is interactive, so this only bounds a dialog that was abandoned on another workspace.
const PICKER_TIMEOUT: Duration = Duration::from_secs(600);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum MoveError {
    InvalidSource,
    InvalidTarget,
    TargetNotEmpty,
    Copy,
    Publish,
}

impl MoveError {
    fn code(self) -> &'static str {
        match self {
            MoveError::InvalidTarget => "data_directory_invalid",
            MoveError::TargetNotEmpty => "data_directory_not_empty",
            MoveError::InvalidSource => "data_directory_unavailable",
            MoveError::Copy | MoveError::Publish => "data_directory_move_failed",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct MoveOutcome {
    pub retained_old_data: bool,
}

struct LocatorBackup {
    path: PathBuf,
    contents: Vec<u8>,
}

fn is_pinned(name: &std::ffi::OsStr) -> bool {
    let Some(name) = name.to_str() else {
        return false;
    };
    // A provider credential save in flight writes `<file>.new` before its rename.
    PINNED_FILES
        .iter()
        .any(|pinned| name == *pinned || name.strip_suffix(".new") == Some(pinned))
}

/// `$XDG_CONFIG_HOME/msime-client`, or `~/.config/msime-client`. A relative `XDG_CONFIG_HOME` is invalid per the base directory specification and is ignored the same way the setup script ignores it.
pub(crate) fn default_root() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .map(|home| home.join(".config"))
        })?;
    Some(base.join("msime-client"))
}

fn atomic_write(path: &Path, contents: &[u8]) -> io::Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| io::Error::from(io::ErrorKind::InvalidInput))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(contents)?;
    temporary.as_file().sync_all()?;
    let permissions = fs::metadata(path)?.permissions();
    temporary.as_file().set_permissions(permissions)?;
    temporary
        .persist(path)
        .map(|_| ())
        .map_err(|error| error.error)
}

fn copy_entry(source: &Path, destination: &Path) -> Result<(), MoveError> {
    let metadata = fs::symlink_metadata(source).map_err(|_| MoveError::Copy)?;
    if metadata.file_type().is_symlink() {
        return Err(MoveError::Copy);
    }
    if metadata.is_dir() {
        fs::create_dir(destination).map_err(|_| MoveError::Copy)?;
        for entry in fs::read_dir(source).map_err(|_| MoveError::Copy)? {
            let entry = entry.map_err(|_| MoveError::Copy)?;
            copy_entry(&entry.path(), &destination.join(entry.file_name()))?;
        }
        fs::set_permissions(destination, metadata.permissions()).map_err(|_| MoveError::Copy)?;
        return Ok(());
    }
    if !metadata.is_file() {
        return Err(MoveError::Copy);
    }
    fs::copy(source, destination).map_err(|_| MoveError::Copy)?;
    fs::set_permissions(destination, metadata.permissions()).map_err(|_| MoveError::Copy)?;
    fs::File::open(destination)
        .and_then(|file| file.sync_all())
        .map_err(|_| MoveError::Copy)
}

fn remove_entry(path: &Path) -> io::Result<()> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.is_dir() && !metadata.file_type().is_symlink() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
}

fn validate_directory(path: &Path, error: MoveError) -> Result<PathBuf, MoveError> {
    if !path.is_absolute() {
        return Err(error);
    }
    let metadata = fs::symlink_metadata(path).map_err(|_| error)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(error);
    }
    fs::canonicalize(path).map_err(|_| error)
}

fn has_ownership_marker(directory: &Path) -> bool {
    fs::symlink_metadata(directory.join(DATA_DIRECTORY_MARKER))
        .map(|metadata| metadata.is_file())
        .unwrap_or(false)
}

/// The state entries of `source`: everything except the pinned configuration files and the ownership marker.
fn state_entries(source: &Path) -> Result<Vec<OsString>, MoveError> {
    let mut entries = Vec::new();
    for entry in fs::read_dir(source).map_err(|_| MoveError::InvalidSource)? {
        let name = entry.map_err(|_| MoveError::InvalidSource)?.file_name();
        if is_pinned(&name) || name == DATA_DIRECTORY_MARKER {
            continue;
        }
        entries.push(name);
    }
    entries.sort();
    Ok(entries)
}

/// A target may already hold the marker. The default root, as a target when moving back, may also hold its pinned files, and nothing else.
fn target_is_empty(target: &Path, default_root: &Path) -> Result<bool, MoveError> {
    for entry in fs::read_dir(target).map_err(|_| MoveError::InvalidTarget)? {
        let name = entry.map_err(|_| MoveError::InvalidTarget)?.file_name();
        if name == DATA_DIRECTORY_MARKER || (target == default_root && is_pinned(&name)) {
            continue;
        }
        return Ok(false);
    }
    Ok(true)
}

/// Replace the `source` prefix of every absolute path string in `document` with `target`. Strings that are not paths under `source` (resources, models, sockets, preference values) are left alone.
fn rebase_paths(document: &mut Value, source: &Path, target: &Path) {
    match document {
        Value::String(text) => {
            let path = Path::new(text.as_str());
            if !path.is_absolute() {
                return;
            }
            if let Ok(rest) = path.strip_prefix(source) {
                let rebased = if rest.as_os_str().is_empty() {
                    target.to_path_buf()
                } else {
                    target.join(rest)
                };
                if let Some(rebased) = rebased.to_str() {
                    *text = rebased.to_owned();
                }
            }
        }
        Value::Array(values) => values
            .iter_mut()
            .for_each(|value| rebase_paths(value, source, target)),
        Value::Object(values) => values
            .values_mut()
            .for_each(|value| rebase_paths(value, source, target)),
        _ => {}
    }
}

fn rebased_locator(
    path: &Path,
    source: &Path,
    written_source: &Path,
    target: &Path,
) -> Result<(LocatorBackup, Vec<u8>), MoveError> {
    let contents = fs::read(path).map_err(|_| MoveError::Publish)?;
    let mut document: Value = serde_json::from_slice(&contents).map_err(|_| MoveError::Publish)?;
    if !document.is_object() {
        return Err(MoveError::Publish);
    }
    rebase_paths(&mut document, written_source, target);
    if written_source != source {
        rebase_paths(&mut document, source, target);
    }
    let rewritten = serde_json::to_vec_pretty(&document).map_err(|_| MoveError::Publish)?;
    Ok((
        LocatorBackup {
            path: path.to_path_buf(),
            contents,
        },
        rewritten,
    ))
}

fn rollback(target: &Path, placed: &[OsString], wrote_marker: bool, backups: &[LocatorBackup]) {
    for backup in backups {
        let _ = atomic_write(&backup.path, &backup.contents);
    }
    for name in placed {
        let _ = remove_entry(&target.join(name));
    }
    if wrote_marker {
        let _ = fs::remove_file(target.join(DATA_DIRECTORY_MARKER));
    }
}

fn cleanup_source(source: &Path, default_root: &Path, moved: &[OsString]) -> bool {
    if source != default_root && !has_ownership_marker(source) {
        return false;
    }
    let mut complete = true;
    for name in moved {
        complete &= remove_entry(&source.join(name)).is_ok();
    }
    if complete && source != default_root {
        // Only an owned directory that is now empty apart from the marker is removed; anything the user put there stays.
        let _ = fs::remove_file(source.join(DATA_DIRECTORY_MARKER));
        let _ = fs::remove_dir(source);
    }
    complete
}

/// Copy the state entries of `source` into `target`, rewrite the locators to point at `target`, and only then remove the old owned entries. `written_source` is the state root as the locators spell it, which may differ from its canonical form.
pub(crate) fn relocate_state(
    source: &Path,
    written_source: &Path,
    target: &Path,
    default_root: &Path,
    locators: &[PathBuf],
) -> Result<MoveOutcome, MoveError> {
    let source = validate_directory(source, MoveError::InvalidSource)?;
    let target = validate_directory(target, MoveError::InvalidTarget)?;
    let default_root = fs::canonicalize(default_root).map_err(|_| MoveError::InvalidSource)?;
    if source == target {
        return Ok(MoveOutcome {
            retained_old_data: false,
        });
    }
    if target.parent().is_none()
        || target.starts_with(&source)
        || source.starts_with(&target)
        || (target != default_root && target.starts_with(&default_root))
    {
        return Err(MoveError::InvalidTarget);
    }
    if !target_is_empty(&target, &default_root)? {
        return Err(MoveError::TargetNotEmpty);
    }
    let entries = state_entries(&source)?;

    let mut unique = BTreeSet::new();
    let mut rewrites = Vec::new();
    for locator in locators {
        if unique.insert(fs::canonicalize(locator).unwrap_or_else(|_| locator.clone())) {
            rewrites.push(rebased_locator(locator, &source, written_source, &target)?);
        }
    }

    // Stage inside the target so the final renames stay on one filesystem, and a failed copy leaves nothing but the staging directory behind.
    let staging = tempfile::Builder::new()
        .prefix(STAGING_PREFIX)
        .tempdir_in(&target)
        .map_err(|_| MoveError::Copy)?;
    for name in &entries {
        copy_entry(&source.join(name), &staging.path().join(name))?;
    }
    let wrote_marker = target != default_root && !has_ownership_marker(&target);
    if wrote_marker
        && fs::write(
            target.join(DATA_DIRECTORY_MARKER),
            b"Metasequoia IME user data directory.\n",
        )
        .is_err()
    {
        return Err(MoveError::Copy);
    }
    let mut placed = Vec::new();
    for name in &entries {
        if fs::rename(staging.path().join(name), target.join(name)).is_err() {
            rollback(&target, &placed, wrote_marker, &[]);
            return Err(MoveError::Copy);
        }
        placed.push(name.clone());
    }
    drop(staging);

    let mut backups = Vec::new();
    for (backup, rewritten) in rewrites {
        let path = backup.path.clone();
        backups.push(backup);
        if atomic_write(&path, &rewritten).is_err() {
            rollback(&target, &placed, wrote_marker, &backups);
            return Err(MoveError::Publish);
        }
    }

    Ok(MoveOutcome {
        retained_old_data: !cleanup_source(&source, &default_root, &entries),
    })
}

fn find_program(name: &str) -> bool {
    std::env::var_os("PATH").is_some_and(|path| {
        std::env::split_paths(&path).any(|directory| {
            directory.is_absolute()
                && fs::metadata(directory.join(name)).is_ok_and(|metadata| metadata.is_file())
        })
    })
}

/// Ask the desktop's own dialog tool for a directory: KDE ships `kdialog`, GNOME and most others ship `zenity`. Returns `Ok(None)` when the user cancels.
fn pick_directory() -> Result<Option<PathBuf>, &'static str> {
    let kde = std::env::var("XDG_CURRENT_DESKTOP")
        .is_ok_and(|desktop| desktop.split(':').any(|name| name == "KDE"));
    let mut tools: Vec<(&str, &[&str])> = vec![
        (
            "zenity",
            &["--file-selection", "--directory", "--title=选择数据目录"],
        ),
        (
            "kdialog",
            &["--getexistingdirectory", "--title", "选择数据目录"],
        ),
    ];
    if kde {
        tools.reverse();
    }
    let (program, arguments) = tools
        .into_iter()
        .find(|(program, _)| find_program(program))
        .ok_or("data_directory_picker_unavailable")?;
    // Both tools exit non-zero on cancel, which the bounded reader reports as no output.
    let Some(output) = linux_process::read_text(program, arguments, 4096, PICKER_TIMEOUT) else {
        return Ok(None);
    };
    let chosen = PathBuf::from(output.trim_end_matches('\n'));
    Ok(chosen.is_absolute().then_some(chosen))
}

fn written_state_root(runtime: &RuntimeOptionsState) -> Result<PathBuf, HostActionError> {
    let unavailable = HostActionError {
        code: "data_directory_unavailable",
    };
    let document = runtime.snapshot().map_err(|_| HostActionError {
        code: "data_directory_unavailable",
    })?;
    document
        .get("preferences_directory")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .ok_or(unavailable)
}

#[derive(Default)]
pub(crate) struct DataDirectorySelectionState(Mutex<Option<PathBuf>>);

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DataDirectoryStatus {
    path: String,
    is_default: bool,
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct DataDirectoryMoveResult {
    path: String,
    is_default: bool,
    retained_old_data: bool,
}

fn same_directory(first: &Path, second: &Path) -> bool {
    fs::canonicalize(first).ok() == fs::canonicalize(second).ok()
}

#[tauri::command]
pub(crate) fn data_directory_status(
    runtime: tauri::State<'_, RuntimeOptionsState>,
) -> Result<DataDirectoryStatus, HostActionError> {
    let path = written_state_root(&runtime)?;
    let default = default_root().ok_or(HostActionError {
        code: "data_directory_unavailable",
    })?;
    Ok(DataDirectoryStatus {
        is_default: same_directory(&path, &default),
        path: path.to_string_lossy().into_owned(),
    })
}

#[tauri::command]
pub(crate) async fn pick_data_directory(
    selection: tauri::State<'_, DataDirectorySelectionState>,
) -> Result<Option<String>, HostActionError> {
    let chosen = tauri::async_runtime::spawn_blocking(pick_directory)
        .await
        .map_err(|_| HostActionError {
            code: "data_directory_unavailable",
        })?
        .map_err(|code| HostActionError { code })?;
    *selection.0.lock().map_err(|_| HostActionError {
        code: "data_directory_unavailable",
    })? = chosen.clone();
    Ok(chosen.map(|path| path.to_string_lossy().into_owned()))
}

#[tauri::command]
pub(crate) async fn move_data_directory(
    app: tauri::AppHandle,
    runtime: tauri::State<'_, RuntimeOptionsState>,
    selection: tauri::State<'_, DataDirectorySelectionState>,
) -> Result<DataDirectoryMoveResult, HostActionError> {
    let written_source = written_state_root(&runtime)?;
    let target = selection
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "data_directory_unavailable",
        })?
        .take()
        .ok_or(HostActionError {
            code: "data_directory_invalid",
        })?;
    let default = default_root().ok_or(HostActionError {
        code: "data_directory_unavailable",
    })?;
    // The file this window reads and the fixed per-user locator every input method reads; normally the same file.
    let mut locators: Vec<PathBuf> = runtime.path.iter().cloned().collect();
    let default_locator = default.join(OPTIONS_FILE);
    if default_locator.is_file() {
        locators.push(default_locator);
    }
    if locators.is_empty() {
        return Err(HostActionError {
            code: "data_directory_unavailable",
        });
    }

    let moved_target = target.clone();
    let outcome = tauri::async_runtime::spawn_blocking(move || {
        let outcome = relocate_state(
            &written_source,
            &written_source,
            &moved_target,
            &default,
            &locators,
        )
        .map(|outcome| (outcome, same_directory(&moved_target, &default)));
        // Engines already running keep the old paths until their session is rebuilt; restarting the framework rebuilds them now instead of on the next focus change. A failed restart does not undo a completed move.
        if outcome.is_ok() {
            let _ = crate::restart_input_method();
        }
        outcome
    })
    .await
    .map_err(|_| HostActionError {
        code: "data_directory_move_failed",
    })?
    .map_err(|error| HostActionError { code: error.code() })?;

    let exit_app = app.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(500));
        exit_app.exit(0);
    });
    Ok(DataDirectoryMoveResult {
        path: fs::canonicalize(&target)
            .unwrap_or(target)
            .to_string_lossy()
            .into_owned(),
        is_default: outcome.1,
        retained_old_data: outcome.0.retained_old_data,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tempfile::tempdir;

    struct Layout {
        _root: tempfile::TempDir,
        default: PathBuf,
        target: PathBuf,
        locator: PathBuf,
    }

    fn setup() -> Layout {
        let root = tempdir().unwrap();
        let base = fs::canonicalize(root.path()).unwrap();
        let default = base.join("config/msime-client");
        let target = base.join("chosen-empty");
        fs::create_dir_all(default.join("user")).unwrap();
        fs::create_dir_all(&target).unwrap();
        fs::write(default.join("preferences.json"), b"synthetic-preferences").unwrap();
        fs::write(default.join("user/msime_user.db"), b"synthetic-dictionary").unwrap();
        fs::write(default.join("ai-provider.json"), b"synthetic-credential").unwrap();
        let locator = default.join(OPTIONS_FILE);
        let document = json!({
            "resources": base.join("resources"),
            "user_data": default.join("user"),
            "cache": default.join("cache"),
            "preferences_directory": default,
            "dictionaries": [{"path": default.join("user/msime_user.db")}],
            "online_provider_socket": "/run/user/1000/msime-client/online.sock",
        });
        fs::write(&locator, serde_json::to_vec_pretty(&document).unwrap()).unwrap();
        Layout {
            _root: root,
            default,
            target,
            locator,
        }
    }

    fn locator_document(layout: &Layout) -> Value {
        serde_json::from_slice(&fs::read(&layout.locator).unwrap()).unwrap()
    }

    #[test]
    fn moves_state_and_rebases_only_the_state_paths_of_the_fixed_locator() {
        let layout = setup();
        let outcome = relocate_state(
            &layout.default,
            &layout.default,
            &layout.target,
            &layout.default,
            std::slice::from_ref(&layout.locator),
        )
        .unwrap();
        assert!(!outcome.retained_old_data);
        assert_eq!(
            fs::read(layout.target.join("user/msime_user.db")).unwrap(),
            b"synthetic-dictionary"
        );
        assert!(layout.target.join(DATA_DIRECTORY_MARKER).is_file());
        assert!(!layout.default.join("preferences.json").exists());
        assert!(!layout.default.join("user").exists());
        // The locator and the provider credentials stay where the services look for them.
        assert!(layout.locator.is_file());
        assert!(layout.default.join("ai-provider.json").is_file());
        assert!(!layout.target.join("ai-provider.json").exists());
        assert!(!layout.target.join(OPTIONS_FILE).exists());
        let document = locator_document(&layout);
        assert_eq!(document["preferences_directory"], json!(layout.target));
        assert_eq!(document["user_data"], json!(layout.target.join("user")));
        assert_eq!(
            document["dictionaries"][0]["path"],
            json!(layout.target.join("user/msime_user.db"))
        );
        assert_eq!(
            document["online_provider_socket"],
            "/run/user/1000/msime-client/online.sock"
        );
        assert_ne!(
            document["resources"],
            json!(layout.target.join("resources"))
        );
    }

    #[test]
    fn moving_back_to_the_default_root_removes_the_owned_custom_directory() {
        let layout = setup();
        let locators = [layout.locator.clone()];
        relocate_state(
            &layout.default,
            &layout.default,
            &layout.target,
            &layout.default,
            &locators,
        )
        .unwrap();
        let outcome = relocate_state(
            &layout.target,
            &layout.target,
            &layout.default,
            &layout.default,
            &locators,
        )
        .unwrap();
        assert!(!outcome.retained_old_data);
        assert!(!layout.target.exists());
        assert_eq!(
            fs::read(layout.default.join("preferences.json")).unwrap(),
            b"synthetic-preferences"
        );
        assert!(!layout.default.join(DATA_DIRECTORY_MARKER).exists());
        assert_eq!(
            locator_document(&layout)["preferences_directory"],
            json!(layout.default)
        );
    }

    #[test]
    fn refuses_nonempty_nested_and_symlinked_targets_without_touching_anything() {
        let layout = setup();
        let locators = [layout.locator.clone()];
        let before = fs::read(&layout.locator).unwrap();
        fs::write(layout.target.join("unrelated.txt"), b"keep").unwrap();
        assert_eq!(
            relocate_state(
                &layout.default,
                &layout.default,
                &layout.target,
                &layout.default,
                &locators
            ),
            Err(MoveError::TargetNotEmpty)
        );
        let nested = layout.default.join("user/nested");
        fs::create_dir(&nested).unwrap();
        assert_eq!(
            relocate_state(
                &layout.default,
                &layout.default,
                &nested,
                &layout.default,
                &locators
            ),
            Err(MoveError::InvalidTarget)
        );
        let link = layout.default.parent().unwrap().join("linked-target");
        std::os::unix::fs::symlink(&layout.target, &link).unwrap();
        assert_eq!(
            relocate_state(
                &layout.default,
                &layout.default,
                &link,
                &layout.default,
                &locators
            ),
            Err(MoveError::InvalidTarget)
        );
        assert_eq!(fs::read(&layout.locator).unwrap(), before);
        assert!(layout.default.join("preferences.json").is_file());
        assert_eq!(
            fs::read(layout.target.join("unrelated.txt")).unwrap(),
            b"keep"
        );
    }

    #[test]
    fn unreadable_locator_aborts_before_any_state_is_copied() {
        let layout = setup();
        fs::write(&layout.locator, b"not json").unwrap();
        assert_eq!(
            relocate_state(
                &layout.default,
                &layout.default,
                &layout.target,
                &layout.default,
                std::slice::from_ref(&layout.locator),
            ),
            Err(MoveError::Publish)
        );
        assert!(fs::read_dir(&layout.target).unwrap().next().is_none());
        assert!(layout.default.join("preferences.json").is_file());
    }

    #[test]
    fn unowned_custom_source_is_copied_but_never_deleted() {
        let layout = setup();
        let source = layout.default.parent().unwrap().join("external-source");
        fs::create_dir(&source).unwrap();
        fs::write(source.join("preferences.json"), b"synthetic").unwrap();
        let outcome = relocate_state(
            &source,
            &source,
            &layout.target,
            &layout.default,
            std::slice::from_ref(&layout.locator),
        )
        .unwrap();
        assert!(outcome.retained_old_data);
        assert!(source.join("preferences.json").is_file());
        assert!(layout.target.join("preferences.json").is_file());
    }

    #[test]
    fn pinned_files_include_in_flight_credential_writes() {
        assert!(is_pinned(std::ffi::OsStr::new("voice-provider.json.new")));
        assert!(is_pinned(std::ffi::OsStr::new(OPTIONS_FILE)));
        assert!(!is_pinned(std::ffi::OsStr::new("preferences.json")));
        assert!(!is_pinned(std::ffi::OsStr::new("skins")));
    }
}

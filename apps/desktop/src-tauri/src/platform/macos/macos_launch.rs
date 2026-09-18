//! Resolve the same prepared configuration used by the macOS input method.
use serde_json::Value;
use std::ffi::OsString;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

const MAX_OPTIONS_BYTES: u64 = 1024 * 1024;

pub(crate) struct LaunchState {
    pub options_path: PathBuf,
    pub preferences_directory: PathBuf,
    pub document: Value,
}

#[cfg(test)]
pub(crate) fn resolve(
    application_directory: &Path,
    options_override: Option<OsString>,
    state_override: Option<OsString>,
) -> Result<LaunchState, &'static str> {
    resolve_with_resources(
        application_directory,
        None,
        options_override,
        state_override,
    )
}

pub(crate) fn resolve_with_resources(
    application_directory: &Path,
    resources_directory: Option<&Path>,
    options_override: Option<OsString>,
    state_override: Option<OsString>,
) -> Result<LaunchState, &'static str> {
    if !application_directory.is_absolute() {
        return Err("Application data directory must be absolute");
    }
    let state_directory = state_override.as_deref().map(PathBuf::from);
    if let Some(state_directory) = state_directory.as_ref() {
        if !state_directory.is_absolute() {
            return Err("Runtime preferences directory must be an absolute path");
        }
    }
    let using_default_options = options_override.is_none();
    let options_path = options_override
        .map(PathBuf::from)
        .unwrap_or_else(|| application_directory.join("runtime-options.json"));
    if !options_path.is_absolute() {
        return Err("HostOptions path must be absolute");
    }
    if using_default_options && !options_path.exists() {
        let resources = resources_directory.ok_or("Cannot read prepared HostOptions JSON")?;
        let state_root = state_directory.as_deref().unwrap_or(application_directory);
        prepare_default_options(resources, state_root, &options_path)?;
    }
    let file =
        std::fs::File::open(&options_path).map_err(|_| "Cannot read prepared HostOptions JSON")?;
    let mut bytes = Vec::new();
    file.take(MAX_OPTIONS_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "Cannot read prepared HostOptions JSON")?;
    if bytes.len() as u64 > MAX_OPTIONS_BYTES {
        return Err("Prepared HostOptions JSON exceeds size limit");
    }
    let document: Value =
        serde_json::from_slice(&bytes).map_err(|_| "Cannot parse prepared HostOptions JSON")?;
    if !document.is_object() {
        return Err("Prepared HostOptions JSON must be an object");
    }
    let preferences_directory = match state_directory {
        Some(value) => value,
        None => match document.get("preferences_directory") {
            None | Some(Value::Null) => application_directory.to_path_buf(),
            Some(Value::String(value)) if value.is_empty() => application_directory.to_path_buf(),
            Some(Value::String(value)) => PathBuf::from(value),
            _ => return Err("Runtime preferences directory must be an absolute path"),
        },
    };
    if !preferences_directory.is_absolute() {
        return Err("Runtime preferences directory must be an absolute path");
    }
    Ok(LaunchState {
        options_path,
        preferences_directory,
        document,
    })
}

fn prepare_default_options(
    resources_directory: &Path,
    state_root: &Path,
    options_path: &Path,
) -> Result<(), &'static str> {
    std::fs::create_dir_all(state_root).map_err(|_| "Cannot prepare default HostOptions JSON")?;
    let document = msime_host_api::prepare_host_configuration(resources_directory, state_root)
        .map_err(|_| "Cannot prepare default HostOptions JSON")?;
    let document: Value =
        serde_json::from_str(&document).map_err(|_| "Cannot prepare default HostOptions JSON")?;
    if !document.is_object() {
        return Err("Cannot prepare default HostOptions JSON");
    }
    publish_options(options_path, &document)
}

fn publish_options(options_path: &Path, document: &Value) -> Result<(), &'static str> {
    let parent = options_path
        .parent()
        .ok_or("Cannot prepare default HostOptions JSON")?;
    std::fs::create_dir_all(parent).map_err(|_| "Cannot prepare default HostOptions JSON")?;
    let serialized = serde_json::to_vec_pretty(document)
        .map_err(|_| "Cannot prepare default HostOptions JSON")?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)
        .map_err(|_| "Cannot prepare default HostOptions JSON")?;
    temporary
        .write_all(&serialized)
        .and_then(|_| temporary.as_file().sync_all())
        .map_err(|_| "Cannot prepare default HostOptions JSON")?;
    match temporary.persist_noclobber(options_path) {
        Ok(_) => Ok(()),
        Err(error) if error.error.kind() == std::io::ErrorKind::AlreadyExists => Ok(()),
        Err(_) => Err("Cannot prepare default HostOptions JSON"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use msime_client_core::preferences::PreferencesStore;
    use serde_json::json;

    #[test]
    fn finder_launch_uses_native_default_configuration_without_environment() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("runtime-options.json");
        let document = json!({"api_version":1,"resources":"synthetic-resources"});
        std::fs::write(&path, document.to_string()).unwrap();
        let launch = resolve(root.path(), None, None).unwrap();
        assert_eq!(launch.options_path, path);
        assert_eq!(launch.preferences_directory, root.path());
        assert_eq!(launch.document, document);
    }

    #[test]
    fn missing_configuration_is_published_atomically_without_overwriting_existing_state() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("runtime-options.json");
        let first = json!({"api_version":1,"resources":"first"});
        let second = json!({"api_version":1,"resources":"second"});
        publish_options(&path, &first).unwrap();
        publish_options(&path, &second).unwrap();
        assert_eq!(
            serde_json::from_slice::<Value>(&std::fs::read(path).unwrap()).unwrap(),
            first
        );
    }

    #[test]
    fn explicit_options_override_never_triggers_default_preparation() {
        let root = tempfile::tempdir().unwrap();
        let app = root.path().join("app");
        let explicit = root.path().join("explicit-runtime-options.json");
        let missing_resources = root.path().join("missing-resources");
        assert!(resolve_with_resources(
            &app,
            Some(&missing_resources),
            Some(explicit.into_os_string()),
            None,
        )
        .is_err());
        assert!(!app.exists());
    }

    #[test]
    fn native_launch_saves_to_the_hosts_preferences_directory() {
        let root = tempfile::tempdir().unwrap();
        let app = root.path().join("app");
        let state = root.path().join("共享 配置");
        let path = root.path().join("bundled-runtime-options.json");
        std::fs::write(&path, json!({"preferences_directory":state}).to_string()).unwrap();
        let launch = resolve(&app, Some(path.clone().into_os_string()), None).unwrap();
        let store = PreferencesStore::new(&launch.preferences_directory);
        let initial = store.load().unwrap();
        let mut preferences = initial.preferences;
        preferences.candidate_page_size = 7;
        store.save(initial.revision, preferences).unwrap();
        let native = PreferencesStore::new(&state).load().unwrap();
        assert_eq!(native.preferences.candidate_page_size, 7);
        assert!(!app.exists(), "must not create a second preferences store");
        assert_eq!(launch.options_path, path);
    }

    #[test]
    fn explicit_state_override_does_not_change_the_selected_options_file() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("runtime-options.json");
        std::fs::write(
            &path,
            json!({"preferences_directory":root.path().join("native")}).to_string(),
        )
        .unwrap();
        let override_path = root.path().join("explicit-state");
        let launch = resolve(
            root.path(),
            None,
            Some(override_path.clone().into_os_string()),
        )
        .unwrap();
        assert_eq!(launch.preferences_directory, override_path);
        assert_eq!(launch.options_path, path);
    }

    #[test]
    fn bad_explicit_paths_never_fall_back_to_another_store() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("runtime-options.json");
        std::fs::write(&path, "{}").unwrap();
        for value in [OsString::new(), OsString::from("relative.json")] {
            assert!(resolve(root.path(), Some(value.clone()), None).is_err());
            assert!(resolve(root.path(), None, Some(value)).is_err());
        }
        assert!(resolve(
            root.path(),
            Some(root.path().join("missing").into_os_string()),
            None
        )
        .is_err());
        for value in [json!("relative"), json!(42), json!([])] {
            std::fs::write(&path, json!({"preferences_directory":value}).to_string()).unwrap();
            assert!(resolve(root.path(), None, None).is_err());
        }
    }

    #[test]
    fn invalid_documents_are_bounded_and_errors_do_not_expose_contents_or_paths() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("runtime-options.json");
        for bytes in [
            "synthetic-private-config".to_owned(),
            "[]".into(),
            "x".repeat(MAX_OPTIONS_BYTES as usize + 1),
        ] {
            std::fs::write(&path, bytes).unwrap();
            let error = resolve(root.path(), None, None).err().unwrap();
            assert!(!error.contains("synthetic-private-config"));
            assert!(!error.contains(&root.path().to_string_lossy().to_string()));
        }
    }
}

//! Resolve the same prepared configuration used by the macOS input method.
use serde_json::Value;
use std::ffi::OsString;
use std::io::Read;
use std::path::{Path, PathBuf};

const MAX_OPTIONS_BYTES: u64 = 1024 * 1024;

pub(crate) struct LaunchState {
    pub options_path: PathBuf,
    pub preferences_directory: PathBuf,
    pub document: Value,
}

pub(crate) fn resolve(
    application_directory: &Path,
    options_override: Option<OsString>,
    state_override: Option<OsString>,
) -> Result<LaunchState, &'static str> {
    if !application_directory.is_absolute() {
        return Err("Application data directory must be absolute");
    }
    let options_path = options_override
        .map(PathBuf::from)
        .unwrap_or_else(|| application_directory.join("runtime-options.json"));
    if !options_path.is_absolute() {
        return Err("HostOptions path must be absolute");
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
    let preferences_directory = match state_override {
        Some(value) => PathBuf::from(value),
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

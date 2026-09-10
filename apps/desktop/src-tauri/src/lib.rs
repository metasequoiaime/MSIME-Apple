use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use std::sync::Arc;
use tauri::Manager;

struct DictionaryHostOptions(Arc<String>);

#[derive(serde::Serialize)]
struct CommandError {
    code: &'static str,
}

impl From<PreferencesError> for CommandError {
    fn from(value: PreferencesError) -> Self {
        Self {
            code: match value {
                PreferencesError::Conflict => "conflict",
                PreferencesError::InvalidPageSize => "invalid",
                PreferencesError::InvalidFrequency => "frequency_invalid",
                PreferencesError::InvalidMixedInput => "mixed_input_invalid",
                PreferencesError::InvalidAiAssistant => "ai_invalid",
                PreferencesError::ConflictingKeyBindings => "key_conflict",
                PreferencesError::UnsupportedFormat | PreferencesError::Json(_) => "format",
                _ => "storage",
            },
        }
    }
}

#[tauri::command]
async fn load_preferences(
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<PreferencesSnapshot, CommandError> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || store.load().map_err(CommandError::from))
        .await
        .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn save_preferences(
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    expected_revision: u64,
    preferences: Preferences,
) -> Result<PreferencesSnapshot, CommandError> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        store
            .save(expected_revision, preferences)
            .map_err(CommandError::from)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn dictionary_request(
    state: tauri::State<'_, DictionaryHostOptions>,
    action: serde_json::Value,
) -> Result<serde_json::Value, CommandError> {
    let options = state.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let options: serde_json::Value =
            serde_json::from_str(&options).map_err(|_| CommandError { code: "storage" })?;
        let request = serde_json::json!({ "options": options, "action": action });
        let bytes = serde_json::to_vec(&request).map_err(|_| CommandError { code: "storage" })?;
        let result = msime_host_api::dictionary_request_json(&bytes)
            .map_err(|_| CommandError { code: "storage" })?;
        if result["ok"] != true {
            return Err(CommandError { code: "storage" });
        }
        Ok(result["value"].clone())
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            #[cfg(target_os = "android")]
            let directory = app.path().app_data_dir()?.join("files/bootstrap/state");
            #[cfg(not(target_os = "android"))]
            let directory = match std::env::var_os("MSIME_CLIENT_STATE_DIR") {
                Some(value) => {
                    let path = std::path::PathBuf::from(value);
                    if !path.is_absolute() {
                        return Err("MSIME_CLIENT_STATE_DIR must be absolute".into());
                    }
                    path
                }
                None => app.path().app_data_dir()?,
            };
            app.manage(std::sync::Arc::new(PreferencesStore::new(directory)));
            // Native packaging/installer supplies this verified JSON after resource
            // generation; never let a webview choose resource or state paths.
            let host_options = std::env::var_os("MSIME_CLIENT_HOST_OPTIONS")
                .and_then(|value| std::fs::read_to_string(value).ok())
                .ok_or_else(|| {
                    "MSIME_CLIENT_HOST_OPTIONS must point to a prepared HostOptions JSON"
                        .to_string()
                })?;
            app.manage(DictionaryHostOptions(Arc::new(host_options)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_preferences,
            save_preferences,
            dictionary_request
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

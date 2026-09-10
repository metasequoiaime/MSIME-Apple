use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::Manager;

struct DictionaryHostOptions(Arc<String>);
struct DiagnosticState(std::sync::Mutex<(bool, bool)>);
struct ClipboardHistoryState(std::sync::Mutex<Vec<String>>);
struct SkinState(std::sync::Mutex<Option<String>>);

#[derive(Debug, serde::Serialize)]
struct ExternalSkinSummary {
    id: String,
    name: String,
    version: Option<String>,
    author: Option<String>,
    description: Option<String>,
    compatible: bool,
}

#[derive(Debug, serde::Deserialize, Default)]
#[serde(default)]
struct SkinManifest {
    name: Option<String>,
    version: Option<String>,
    author: Option<String>,
    description: Option<String>,
    base: Option<String>,
    layouts: Vec<String>,
    themes: Vec<String>,
}

fn skin_directory(app: &tauri::AppHandle) -> Result<PathBuf, HostActionError> {
    app.path()
        .app_data_dir()
        .map(|path| path.join("skins"))
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[tauri::command]
fn open_skin_directory(app: tauri::AppHandle) -> Result<(), HostActionError> {
    let path = skin_directory(&app)?;
    std::fs::create_dir_all(&path).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    let value = path.to_string_lossy().into_owned();
    #[cfg(target_os = "macos")]
    {
        return run_external_command("open", &[&value]);
    }
    #[cfg(target_os = "linux")]
    {
        return run_external_command("xdg-open", &[&value]);
    }
    #[cfg(target_os = "windows")]
    {
        return run_external_command("explorer", &[&value]);
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        let _ = value;
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn refresh_skin_catalog(app: tauri::AppHandle) -> Result<(), HostActionError> {
    std::fs::create_dir_all(skin_directory(&app)?).map_err(|_| HostActionError {
        code: "unavailable",
    })
}

#[tauri::command]
fn list_external_skins(app: tauri::AppHandle) -> Result<Vec<ExternalSkinSummary>, HostActionError> {
    let path = skin_directory(&app)?;
    let mut result = Vec::new();
    let entries = match std::fs::read_dir(path) {
        Ok(entries) => entries,
        Err(_) => return Ok(result),
    };
    for entry in entries.flatten() {
        if !entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false) {
            continue;
        }
        let id = entry.file_name().to_string_lossy().into_owned();
        let manifest = entry.path().join("skin.toml");
        if !manifest.is_file() {
            continue;
        }
        let text = match std::fs::read_to_string(manifest) {
            Ok(text) => text,
            Err(_) => continue,
        };
        let manifest: SkinManifest = match toml::from_str(&text) {
            Ok(manifest) => manifest,
            Err(_) => continue,
        };
        let compatible = matches!(
            manifest.base.as_deref(),
            Some("fluent" | "wechat" | "graphite" | "willow_green")
        ) && manifest.layouts.iter().any(|value| value == "horizontal")
            && manifest.layouts.iter().any(|value| value == "vertical")
            && manifest.themes.iter().any(|value| value == "dark")
            && manifest.themes.iter().any(|value| value == "light");
        result.push(ExternalSkinSummary {
            name: manifest
                .name
                .filter(|value| !value.is_empty())
                .unwrap_or_else(|| id.clone()),
            id,
            version: manifest.version,
            author: manifest.author,
            description: manifest.description,
            compatible,
        });
    }
    Ok(result)
}

#[tauri::command]
fn select_skin(
    app: tauri::AppHandle,
    state: tauri::State<'_, SkinState>,
    id: String,
) -> Result<(), HostActionError> {
    if id.is_empty()
        || id.len() > 128
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
    {
        return Err(HostActionError {
            code: "invalid_skin",
        });
    }
    let path = app
        .path()
        .app_data_dir()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .join("selected-skin");
    std::fs::write(path, &id).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    *state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })? = Some(id);
    Ok(())
}

#[tauri::command]
fn selected_skin(app: tauri::AppHandle) -> Result<Option<String>, HostActionError> {
    let path = app
        .path()
        .app_data_dir()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .join("selected-skin");
    match std::fs::read_to_string(path) {
        Ok(id) if !id.is_empty() => Ok(Some(id)),
        Ok(_) | Err(_) => Ok(None),
    }
}

#[derive(Debug, serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

#[tauri::command]
fn clear_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<(), HostActionError> {
    state
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .clear();
    Ok(())
}

#[tauri::command]
fn set_diagnostic_log(
    state: tauri::State<'_, DiagnosticState>,
    scope: String,
    enabled: bool,
) -> Result<(), HostActionError> {
    let mut values = state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    match scope.as_str() {
        "server" => values.0 = enabled,
        "tsf" => values.1 = enabled,
        _ => {
            return Err(HostActionError {
                code: "invalid_scope",
            });
        }
    }
    Ok(())
}

fn run_external_command(program: &str, args: &[&str]) -> Result<(), HostActionError> {
    std::process::Command::new(program)
        .args(args)
        .spawn()
        .map(|_| ())
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[tauri::command]
fn open_external_url(url: String) -> Result<(), HostActionError> {
    if !is_allowed_external_url(&url) {
        return Err(HostActionError {
            code: "invalid_url",
        });
    }
    #[cfg(target_os = "macos")]
    {
        return run_external_command("open", &[&url]);
    }
    #[cfg(target_os = "linux")]
    {
        return run_external_command("xdg-open", &[&url]);
    }
    #[cfg(target_os = "windows")]
    {
        return run_external_command("cmd", &["/C", "start", "", &url]);
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        let _ = url;
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

fn is_allowed_external_url(url: &str) -> bool {
    let allowed = [
        "https://github.com/metasequoiaime/MSIME-Client",
        "https://github.com/metasequoiaime/MSIME-Windows",
        "https://t.me/msimegroup",
    ];
    allowed.iter().any(|prefix| url.starts_with(prefix))
        && !url.chars().any(|character| {
            character.is_whitespace()
                || character.is_control()
                || matches!(character, '&' | '|' | '<' | '>' | '^' | '%')
        })
}

#[cfg(test)]
mod tests {
    use super::is_allowed_external_url;

    #[test]
    fn external_url_allowlist_rejects_shell_metacharacters() {
        assert!(is_allowed_external_url(
            "https://github.com/metasequoiaime/MSIME-Client/releases"
        ));
        assert!(is_allowed_external_url("https://t.me/msimegroup"));
        assert!(!is_allowed_external_url("https://example.com"));
        assert!(!is_allowed_external_url(
            "https://github.com/metasequoiaime/MSIME-Client&bad"
        ));
    }
}

#[tauri::command]
fn check_for_updates() -> Result<(), HostActionError> {
    open_external_url("https://github.com/metasequoiaime/MSIME-Client/releases".to_string())
}

#[tauri::command]
fn open_screen_keyboard() -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        return run_external_command("onboard", &[]);
    }
    #[cfg(target_os = "macos")]
    {
        return run_external_command("open", &["/System/Library/CoreServices/KeyboardViewer.app"]);
    }
    #[cfg(target_os = "windows")]
    {
        return run_external_command("osk.exe", &[]);
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn copy_text(text: String) -> Result<(), HostActionError> {
    #[cfg(target_os = "macos")]
    {
        let mut child = std::process::Command::new("pbcopy")
            .stdin(std::process::Stdio::piped())
            .spawn()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        child
            .stdin
            .take()
            .ok_or(HostActionError {
                code: "unavailable",
            })?
            .write_all(text.as_bytes())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    #[cfg(target_os = "linux")]
    {
        let mut child = std::process::Command::new("xclip")
            .args(["-selection", "clipboard"])
            .stdin(std::process::Stdio::piped())
            .spawn()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        child
            .stdin
            .take()
            .ok_or(HostActionError {
                code: "unavailable",
            })?
            .write_all(text.as_bytes())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    #[cfg(target_os = "windows")]
    {
        let mut child = std::process::Command::new("clip")
            .stdin(std::process::Stdio::piped())
            .spawn()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        child
            .stdin
            .take()
            .ok_or(HostActionError {
                code: "unavailable",
            })?
            .write_all(text.as_bytes())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    {
        let _ = text;
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

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
            app.manage(DiagnosticState(std::sync::Mutex::new((false, false))));
            app.manage(ClipboardHistoryState(std::sync::Mutex::new(Vec::new())));
            let selected_skin = app
                .path()
                .app_data_dir()
                .ok()
                .and_then(|path| std::fs::read_to_string(path.join("selected-skin")).ok())
                .filter(|id| !id.is_empty());
            app.manage(SkinState(std::sync::Mutex::new(selected_skin)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_preferences,
            save_preferences,
            dictionary_request,
            open_external_url,
            check_for_updates,
            open_screen_keyboard,
            copy_text,
            open_skin_directory,
            refresh_skin_catalog,
            list_external_skins,
            set_diagnostic_log,
            clear_clipboard_history,
            select_skin,
            selected_skin
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

use msime_client_core::clipboard::ClipboardHistoryStore;
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use tauri::Manager;

struct ClipboardHistoryState(std::sync::Mutex<ClipboardHistoryStore>);

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

#[derive(serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

fn clipboard_enabled(store: &std::sync::Arc<PreferencesStore>) -> Result<bool, HostActionError> {
    store
        .load()
        .map(|snapshot| snapshot.preferences.clipboard_history)
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[tauri::command]
fn list_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<Vec<String>, HostActionError> {
    if !clipboard_enabled(store.inner())? {
        return Ok(Vec::new());
    }
    state
        .0
        .lock()
        .map(|history| history.entries().to_vec())
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
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
        .clear()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[tauri::command]
fn sync_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<Vec<String>, HostActionError> {
    if !clipboard_enabled(store.inner())? {
        return Err(HostActionError { code: "disabled" });
    }
    #[cfg(target_os = "macos")]
    let output = std::process::Command::new("pbpaste").output();
    #[cfg(target_os = "linux")]
    let output = std::process::Command::new("xclip")
        .args(["-selection", "clipboard", "-o"])
        .output();
    #[cfg(target_os = "windows")]
    let output = std::process::Command::new("powershell")
        .args(["-NoProfile", "-Command", "Get-Clipboard"])
        .output();
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    let output: Result<std::process::Output, std::io::Error> =
        Err(std::io::Error::other("unsupported"));
    let output = output.map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    if !output.status.success() {
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    let text = String::from_utf8(output.stdout)
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .trim_end_matches(['\r', '\n'])
        .to_owned();
    let mut history = state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    history.push(text).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    Ok(history.entries().to_vec())
}

#[tauri::command]
fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<(), HostActionError> {
    let enabled = clipboard_enabled(store.inner())?;
    #[cfg(target_os = "macos")]
    let result = {
        use std::io::Write;
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
        child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
    };
    #[cfg(target_os = "linux")]
    let result = {
        use std::io::Write;
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
        child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
    };
    #[cfg(target_os = "windows")]
    let result = {
        use std::io::Write;
        let mut child = std::process::Command::new("powershell")
            .args(["-NoProfile", "-Command", "Set-Clipboard"])
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
        child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
    };
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    let result = false;
    if !result {
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    if enabled {
        state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .push(text)
            .map(|_| ())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
    }
    Ok(())
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
            let mut clipboard =
                ClipboardHistoryStore::open(directory.join("clipboard_history.json"));
            let _ = clipboard.load();
            app.manage(std::sync::Arc::new(PreferencesStore::new(&directory)));
            app.manage(ClipboardHistoryState(std::sync::Mutex::new(clipboard)));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_preferences,
            save_preferences,
            list_clipboard_history,
            clear_clipboard_history,
            sync_clipboard_history,
            copy_text
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

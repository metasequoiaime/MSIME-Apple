use msime_client_core::clipboard::ClipboardHistoryStore;
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use std::sync::Arc;
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder};

struct ClipboardHistoryState(std::sync::Mutex<ClipboardHistoryStore>);
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
                PreferencesError::InvalidFloatingToolbar => "floating_toolbar_invalid",
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
        msime_host_api::dictionary_request_json(&bytes)
            .map_err(|_| CommandError { code: "storage" })
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[derive(serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

fn external_url_is_safe(url: &str) -> bool {
    url.starts_with("https://")
        && !url.bytes().any(|byte| {
            byte <= b' '
                || matches!(
                    byte,
                    b'"' | b'\'' | b'`' | b'&' | b'|' | b'<' | b'>' | b'\\'
                )
        })
}

#[tauri::command]
fn open_external_url(url: String) -> Result<(), HostActionError> {
    if !external_url_is_safe(&url) {
        return Err(HostActionError {
            code: "invalid_url",
        });
    }
    #[cfg(target_os = "macos")]
    let result = std::process::Command::new("open").arg(&url).status();
    #[cfg(target_os = "linux")]
    let result = std::process::Command::new("xdg-open").arg(&url).status();
    #[cfg(target_os = "windows")]
    let result = std::process::Command::new("cmd")
        .args(["/C", "start", ""])
        .arg(&url)
        .status();
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    let result: Result<std::process::ExitStatus, std::io::Error> =
        Err(std::io::Error::other("unsupported"));
    match result {
        Ok(status) if status.success() => Ok(()),
        _ => Err(HostActionError {
            code: "unavailable",
        }),
    }
}

fn open_panel_window(
    app: &tauri::AppHandle,
    label: &'static str,
    route: &'static str,
    title: &'static str,
    width: f64,
    height: f64,
) -> Result<(), HostActionError> {
    if let Some(window) = app.get_webview_window(label) {
        window
            .show()
            .and_then(|_| window.set_focus())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    WebviewWindowBuilder::new(
        app,
        label,
        WebviewUrl::App(format!("index.html?panel={route}").into()),
    )
    .title(title)
    .inner_size(width, height)
    .min_inner_size(width, height)
    .resizable(false)
    .decorations(false)
    .always_on_top(true)
    .skip_taskbar(true)
    .build()
    .map(|_| ())
    .map_err(|_| HostActionError {
        code: "unavailable",
    })
}

#[tauri::command]
fn open_keyboard_panel(app: tauri::AppHandle) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = app;
        let executable = std::env::var_os("MSIME_CLIENT_KEYBOARD_PANEL")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::current_exe().ok().and_then(|path| {
                    path.parent()
                        .map(|parent| parent.join("msime-client-keyboard-panel.exe"))
                })
            })
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        std::process::Command::new(executable)
            .spawn()
            .map(|_| ())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    #[cfg(not(target_os = "windows"))]
    open_panel_window(
        &app,
        "keyboard-panel",
        "keyboard",
        "水杉屏幕键盘",
        1100.0,
        400.0,
    )
}

#[tauri::command]
fn open_handwriting_panel(app: tauri::AppHandle) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = app;
        let executable = std::env::var_os("MSIME_CLIENT_HANDWRITING_PANEL")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::current_exe().ok().and_then(|path| {
                    path.parent()
                        .map(|parent| parent.join("msime-client-handwriting-panel.exe"))
                })
            })
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        std::process::Command::new(executable)
            .spawn()
            .map(|_| ())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(());
    }
    #[cfg(not(target_os = "windows"))]
    open_panel_window(
        &app,
        "handwriting-panel",
        "handwriting",
        "水杉手写识别板",
        980.0,
        650.0,
    )
}

#[tauri::command]
fn open_emoji_panel(app: tauri::AppHandle) -> Result<(), HostActionError> {
    open_panel_window(&app, "emoji-panel", "emoji", "Emoji and more", 720.0, 720.0)
}

#[tauri::command]
fn close_panel(app: tauri::AppHandle, label: String) -> Result<(), HostActionError> {
    if !matches!(
        label.as_str(),
        "keyboard-panel" | "handwriting-panel" | "emoji-panel"
    ) {
        return Err(HostActionError {
            code: "invalid_panel",
        });
    }
    app.get_webview_window(&label)
        .ok_or(HostActionError {
            code: "unavailable",
        })?
        .close()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
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
            // Native packaging/installer supplies this verified HostOptions JSON.
            // Webview input never controls resource or state paths.
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
            list_clipboard_history,
            clear_clipboard_history,
            sync_clipboard_history,
            copy_text,
            open_external_url,
            open_keyboard_panel,
            open_handwriting_panel,
            open_emoji_panel,
            close_panel,
            dictionary_request
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

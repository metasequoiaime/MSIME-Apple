use msime_client_core::clipboard::ClipboardHistoryStore;
use msime_client_core::panels::{
    HandwritingRecognitionRequest, HandwritingRecognitionResult, KeyboardInputRequest,
};
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
#[cfg(unix)]
use msime_input_runtime::{HandwritingPoint, HandwritingQuery, UnixSocketProvider};
use serde_json::Value;
#[cfg(unix)]
use std::collections::HashMap;
use std::fs;
#[cfg(target_os = "linux")]
use std::io::Write;
#[cfg(target_os = "linux")]
use std::path::Path;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
#[cfg(target_os = "linux")]
use tauri::Emitter;
use tauri::Manager;
#[cfg(not(target_os = "windows"))]
use tauri::{WebviewUrl, WebviewWindowBuilder};

struct ClipboardHistoryState(Arc<Mutex<ClipboardHistoryStore>>);
struct DictionaryHostOptions(Arc<String>);

#[derive(Clone)]
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
struct RuntimeOptionsState {
    path: Option<PathBuf>,
    document: Arc<Mutex<Value>>,
}

#[derive(Default)]
struct PanelInputState(std::sync::Mutex<Option<PanelInputTarget>>);

#[cfg(target_os = "linux")]
#[derive(Clone, Debug)]
enum PanelInputTarget {
    X11(String),
    Sway(u64),
    Wayland,
}

#[cfg(not(target_os = "linux"))]
#[derive(Clone, Debug)]
struct PanelInputTarget;

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
    runtime: tauri::State<'_, RuntimeOptionsState>,
    expected_revision: u64,
    preferences: Preferences,
) -> Result<PreferencesSnapshot, CommandError> {
    let store = store.inner().clone();
    let runtime = runtime.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let snapshot = store
            .save(expected_revision, preferences)
            .map_err(CommandError::from)?;
        sync_linux_runtime_options(&runtime, &snapshot.preferences)
            .map_err(|_| CommandError { code: "storage" })?;
        Ok(snapshot)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

fn sync_linux_runtime_options(
    runtime: &RuntimeOptionsState,
    preferences: &Preferences,
) -> Result<(), std::io::Error> {
    #[cfg(target_os = "linux")]
    {
        let Some(path) = runtime.path.as_ref() else {
            return Ok(());
        };
        let mut document = runtime
            .document
            .lock()
            .map_err(|_| std::io::Error::other("runtime options lock poisoned"))?;
        document["preferences"] = serde_json::to_value(preferences)
            .map_err(|error| std::io::Error::other(error.to_string()))?;
        let bytes = serde_json::to_vec_pretty(&*document)
            .map_err(|error| std::io::Error::other(error.to_string()))?;
        atomic_write(path, &bytes)?;
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (runtime, preferences);
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn start_linux_preferences_monitor(
    app: &tauri::AppHandle,
    store: std::sync::Arc<PreferencesStore>,
) {
    let app = app.clone();
    let _ = std::thread::Builder::new()
        .name("msime-preferences-monitor".to_owned())
        .spawn(move || {
            let mut revision = store.load().ok().map(|snapshot| snapshot.revision);
            loop {
                std::thread::sleep(std::time::Duration::from_millis(750));
                let Ok(snapshot) = store.load() else {
                    continue;
                };
                if revision == Some(snapshot.revision) {
                    continue;
                }
                revision = Some(snapshot.revision);
                let _ = app.emit("preferences-changed", snapshot);
            }
        });
}

#[cfg(target_os = "linux")]
fn atomic_write(path: &Path, contents: &[u8]) -> Result<(), std::io::Error> {
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(contents)?;
    temporary.as_file().sync_all()?;
    temporary
        .persist(path)
        .map(|_| ())
        .map_err(|error| error.error)
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
struct EmojiCatalogItem {
    text: String,
    keywords: String,
}

#[derive(serde::Serialize)]
struct EmojiCatalogGroup {
    title: String,
    icon: String,
    items: Vec<EmojiCatalogItem>,
}

#[derive(serde::Serialize)]
struct EmojiCatalogResponse {
    emoji: Vec<EmojiCatalogGroup>,
    kaomoji: Vec<EmojiCatalogGroup>,
    symbols: Vec<EmojiCatalogGroup>,
}

#[cfg(unix)]
fn read_local_emoji_groups(
    resources: &str,
    category: &str,
) -> Result<Vec<EmojiCatalogGroup>, &'static str> {
    const PAGE_SIZE: u16 = 512;
    let mut groups = Vec::new();
    let mut positions = HashMap::new();
    let mut offset = 0usize;
    for _ in 0..256 {
        let page =
            msime_host_api::local_emoji_catalog_page(resources, "", category, offset, PAGE_SIZE)?;
        if page.is_empty() {
            break;
        }
        for item in page {
            if item.text.is_empty() {
                continue;
            }
            let title = if item.group.is_empty() {
                "All".to_owned()
            } else {
                item.group
            };
            let index = if let Some(index) = positions.get(&title).copied() {
                index
            } else {
                let index = groups.len();
                positions.insert(title.clone(), index);
                groups.push(EmojiCatalogGroup {
                    title,
                    icon: String::new(),
                    items: Vec::new(),
                });
                index
            };
            let group = &mut groups[index];
            if group.icon.is_empty() {
                group.icon = item.text.chars().next().unwrap_or('•').to_string();
            }
            group.items.push(EmojiCatalogItem {
                keywords: if item.annotation.is_empty() {
                    item.text.clone()
                } else {
                    item.annotation
                },
                text: item.text,
            });
        }
        offset = offset.saturating_add(PAGE_SIZE as usize);
    }
    Ok(groups
        .into_iter()
        .filter(|group| !group.items.is_empty())
        .collect())
}

#[cfg(not(unix))]
fn read_local_emoji_groups(
    _resources: &str,
    _category: &str,
) -> Result<Vec<EmojiCatalogGroup>, &'static str> {
    Err("local emoji catalog unavailable")
}

#[tauri::command]
async fn load_emoji_catalog(
    state: tauri::State<'_, DictionaryHostOptions>,
) -> Result<EmojiCatalogResponse, CommandError> {
    let options = state.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let document: Value =
            serde_json::from_str(&options).map_err(|_| CommandError { code: "storage" })?;
        let resources = document
            .get("resources")
            .and_then(Value::as_str)
            .filter(|value| std::path::Path::new(value).is_absolute())
            .ok_or(CommandError { code: "storage" })?;
        Ok(EmojiCatalogResponse {
            emoji: read_local_emoji_groups(resources, "").map_err(|_| CommandError {
                code: "unavailable",
            })?,
            kaomoji: read_local_emoji_groups(resources, "kaomoji").map_err(|_| CommandError {
                code: "unavailable",
            })?,
            symbols: read_local_emoji_groups(resources, "symbols").map_err(|_| CommandError {
                code: "unavailable",
            })?,
        })
    })
    .await
    .map_err(|_| CommandError {
        code: "unavailable",
    })?
}

#[derive(serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

#[cfg(target_os = "linux")]
fn focused_sway_container(value: &serde_json::Value) -> Option<u64> {
    if value.get("focused").and_then(serde_json::Value::as_bool) == Some(true) {
        if let Some(id) = value.get("id").and_then(serde_json::Value::as_u64) {
            return Some(id);
        }
    }
    for key in ["nodes", "floating_nodes"] {
        if let Some(nodes) = value.get(key).and_then(serde_json::Value::as_array) {
            for node in nodes {
                if let Some(id) = focused_sway_container(node) {
                    return Some(id);
                }
            }
        }
    }
    None
}

#[cfg(target_os = "linux")]
fn sway_rect_for_container(value: &serde_json::Value, id: u64) -> Option<(f64, f64, f64, f64)> {
    if value.get("id").and_then(serde_json::Value::as_u64) == Some(id) {
        let rect = value.get("rect")?;
        return Some((
            rect.get("x")?.as_f64()?,
            rect.get("y")?.as_f64()?,
            rect.get("width")?.as_f64()?,
            rect.get("height")?.as_f64()?,
        ));
    }
    for key in ["nodes", "floating_nodes"] {
        if let Some(nodes) = value.get(key).and_then(serde_json::Value::as_array) {
            for node in nodes {
                if let Some(rect) = sway_rect_for_container(node, id) {
                    return Some(rect);
                }
            }
        }
    }
    None
}

#[cfg(target_os = "linux")]
fn parse_xdotool_geometry(value: &str) -> Option<(f64, f64, f64, f64)> {
    let mut fields = std::collections::HashMap::new();
    for line in value.lines() {
        let (key, value) = line.split_once('=')?;
        fields.insert(key, value.parse::<f64>().ok()?);
    }
    Some((
        *fields.get("X")?,
        *fields.get("Y")?,
        *fields.get("WIDTH")?,
        *fields.get("HEIGHT")?,
    ))
}

#[cfg(target_os = "linux")]
fn panel_position(state: &PanelInputState, width: f64, height: f64) -> Option<(f64, f64)> {
    let target = state.0.lock().ok()?.clone()?;
    let rect = match target {
        PanelInputTarget::X11(window) => std::process::Command::new("xdotool")
            .args(["getwindowgeometry", "--shell", window.as_str()])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .and_then(|output| parse_xdotool_geometry(&String::from_utf8_lossy(&output.stdout))),
        PanelInputTarget::Sway(id) => std::process::Command::new("swaymsg")
            .args(["-t", "get_tree", "-r"])
            .output()
            .ok()
            .filter(|output| output.status.success())
            .and_then(|output| serde_json::from_slice::<serde_json::Value>(&output.stdout).ok())
            .and_then(|tree| sway_rect_for_container(&tree, id)),
        PanelInputTarget::Wayland => None,
    }?;
    let x = (rect.0 + (rect.2 - width) / 2.0).max(0.0);
    let y = (rect.1 + rect.3 - height - 16.0).max(0.0);
    Some((x, y))
}

#[cfg(target_os = "linux")]
fn capture_panel_input_target() -> Result<PanelInputTarget, HostActionError> {
    let wayland_session = std::env::var_os("WAYLAND_DISPLAY").is_some()
        || std::env::var("XDG_SESSION_TYPE").as_deref() == Ok("wayland");
    if wayland_session {
        if let Ok(output) = std::process::Command::new("swaymsg")
            .args(["-t", "get_tree", "-r"])
            .output()
        {
            if output.status.success() {
                if let Ok(tree) = serde_json::from_slice::<serde_json::Value>(&output.stdout) {
                    if let Some(target) = focused_sway_container(&tree).map(PanelInputTarget::Sway)
                    {
                        return Ok(target);
                    }
                }
            }
        }
        if std::process::Command::new("wtype")
            .arg("--version")
            .output()
            .ok()
            .is_some_and(|output| output.status.success())
        {
            return Ok(PanelInputTarget::Wayland);
        }
    }
    if let Ok(output) = std::process::Command::new("xdotool")
        .arg("getactivewindow")
        .output()
    {
        if output.status.success() {
            let id = String::from_utf8_lossy(&output.stdout).trim().to_owned();
            if !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit()) {
                return Ok(PanelInputTarget::X11(id));
            }
        }
    }
    let output = std::process::Command::new("swaymsg")
        .args(["-t", "get_tree", "-r"])
        .output()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    if !output.status.success() {
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    let tree: serde_json::Value =
        serde_json::from_slice(&output.stdout).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    focused_sway_container(&tree)
        .map(PanelInputTarget::Sway)
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn remember_panel_input_target(
    state: &tauri::State<'_, PanelInputState>,
    replace: bool,
) -> Result<(), HostActionError> {
    let mut target = state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    if replace || target.is_none() {
        *target = Some(capture_panel_input_target()?);
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn xdotool_key_name(virtual_key: u16) -> Option<String> {
    let name = match virtual_key {
        0x08 => "BackSpace",
        0x09 => "Tab",
        0x0d => "Return",
        0x20 => "space",
        0x2e => "Delete",
        0x14 => "Caps_Lock",
        0xc0 => "grave",
        0xbd => "minus",
        0xbb => "equal",
        0xdb => "bracketleft",
        0xdd => "bracketright",
        0xdc => "backslash",
        0xba => "semicolon",
        0xde => "apostrophe",
        0xbc => "comma",
        0xbe => "period",
        0xbf => "slash",
        0x30..=0x39 => return char::from_u32(virtual_key as u32).map(|value| value.to_string()),
        0x41..=0x5a => {
            return char::from_u32(virtual_key as u32)
                .map(|value| value.to_ascii_lowercase().to_string());
        }
        _ => return None,
    };
    Some(name.to_owned())
}

#[cfg(target_os = "linux")]
fn xdotool_key_args(request: &KeyboardInputRequest) -> Option<String> {
    let key = xdotool_key_name(request.virtual_key)?;
    let mut parts: Vec<String> = Vec::new();
    if request.include_sticky_modifiers {
        if request.modifiers.ctrl {
            parts.push("ctrl".to_owned());
        }
        if request.modifiers.alt {
            parts.push("alt".to_owned());
        }
        if request.modifiers.win {
            parts.push("super".to_owned());
        }
    }
    if request.shift {
        parts.push("shift".to_owned());
    }
    parts.push(key);
    Some(parts.join("+"))
}

#[cfg(target_os = "linux")]
fn run_wtype(target: &PanelInputTarget, args: &[String]) -> Result<(), HostActionError> {
    if let PanelInputTarget::Sway(id) = target {
        let id = id.to_string();
        let status = std::process::Command::new("swaymsg")
            .arg(format!("[con_id={id}] focus"))
            .status()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        if !status.success() {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
    }
    std::process::Command::new("wtype")
        .args(args)
        .status()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .success()
        .then_some(())
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn send_panel_key(
    state: &tauri::State<'_, PanelInputState>,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_key",
    })?;
    let target = state
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .clone()
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
    if let PanelInputTarget::X11(window) = &target {
        let key = xdotool_key_args(&request).ok_or(HostActionError {
            code: "invalid_key",
        })?;
        let status = std::process::Command::new("xdotool")
            .args(["key", "--window", window.as_str(), key.as_str()])
            .status()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return status.success().then_some(()).ok_or(HostActionError {
            code: "unavailable",
        });
    }
    let key = xdotool_key_name(request.virtual_key).ok_or(HostActionError {
        code: "invalid_key",
    })?;
    let mut args = Vec::new();
    if request.include_sticky_modifiers {
        if request.modifiers.ctrl {
            args.extend(["-M".to_owned(), "ctrl".to_owned()]);
        }
        if request.modifiers.alt {
            args.extend(["-M".to_owned(), "alt".to_owned()]);
        }
        if request.modifiers.win {
            args.extend(["-M".to_owned(), "logo".to_owned()]);
        }
    }
    if request.shift {
        args.extend(["-M".to_owned(), "shift".to_owned()]);
    }
    args.extend(["-k".to_owned(), key.to_owned()]);
    run_wtype(&target, &args)
}

#[cfg(target_os = "linux")]
fn send_panel_text(
    state: &tauri::State<'_, PanelInputState>,
    text: &str,
) -> Result<(), HostActionError> {
    msime_client_core::panels::validate_candidate(text).map_err(|_| HostActionError {
        code: "invalid_text",
    })?;
    let target = state
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .clone()
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
    if let PanelInputTarget::X11(window) = &target {
        let status = std::process::Command::new("xdotool")
            .args(["type", "--window", window.as_str(), "--delay", "0", text])
            .status()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return status.success().then_some(()).ok_or(HostActionError {
            code: "unavailable",
        });
    }
    run_wtype(&target, &["--".to_owned(), text.to_owned()])
}

#[tauri::command]
fn remember_input_target(state: tauri::State<'_, PanelInputState>) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return remember_panel_input_target(&state, false);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = state;
        Ok(())
    }
}

#[tauri::command]
fn send_key(
    state: tauri::State<'_, PanelInputState>,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return send_panel_key(&state, request);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (state, request);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn recognize_handwriting(
    request: HandwritingRecognitionRequest,
) -> Result<HandwritingRecognitionResult, HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_stroke",
    })?;
    #[cfg(unix)]
    {
        let path = std::env::var_os("MSIME_HANDWRITING_PROVIDER_SOCKET")
            .map(std::path::PathBuf::from)
            .filter(|path| path.is_absolute())
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        let query = HandwritingQuery {
            language: request.language,
            strokes: request
                .strokes
                .into_iter()
                .map(|stroke| {
                    stroke
                        .points
                        .into_iter()
                        .map(|point| HandwritingPoint {
                            x: point.x,
                            y: point.y,
                        })
                        .collect()
                })
                .collect(),
        };
        let candidates = tauri::async_runtime::spawn_blocking(move || {
            UnixSocketProvider::new(path).handwriting(query)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
        let result = HandwritingRecognitionResult { candidates };
        result.validate().map_err(|_| HostActionError {
            code: "invalid_stroke",
        })?;
        return Ok(result);
    }
    #[cfg(not(unix))]
    Err(HostActionError {
        code: "unavailable",
    })
}

#[tauri::command]
fn submit_handwriting_candidate(
    state: tauri::State<'_, PanelInputState>,
    candidate: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return send_panel_text(&state, &candidate);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (state, candidate);
        Err(HostActionError {
            code: "unavailable",
        })
    }
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

#[cfg(not(target_os = "windows"))]
fn open_panel_window(
    app: &tauri::AppHandle,
    label: &'static str,
    route: &'static str,
    title: &'static str,
    width: f64,
    height: f64,
    position: Option<(f64, f64)>,
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
    let mut builder = WebviewWindowBuilder::new(
        app,
        label,
        WebviewUrl::App(format!("index.html?panel={route}").into()),
    )
    .title(title);
    if let Some((x, y)) = position {
        builder = builder.position(x, y);
    }
    builder
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
fn open_keyboard_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, state);
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
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 1100.0, 400.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "keyboard-panel",
            "keyboard",
            "水杉屏幕键盘",
            1100.0,
            400.0,
            position,
        )
    }
}

#[tauri::command]
fn open_handwriting_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, state);
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
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 980.0, 650.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "handwriting-panel",
            "handwriting",
            "水杉手写识别板",
            980.0,
            650.0,
            position,
        )
    }
}

#[tauri::command]
fn open_emoji_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, DictionaryHostOptions>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = app;
        let executable = std::env::var_os("MSIME_CLIENT_EMOJI_PANEL")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::current_exe().ok().and_then(|path| {
                    path.parent()
                        .map(|parent| parent.join("msime-client-emoji-panel.exe"))
                })
            })
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        let resources = serde_json::from_str::<serde_json::Value>(&state.0)
            .ok()
            .and_then(|value| {
                value
                    .get("resources")
                    .and_then(serde_json::Value::as_str)
                    .map(str::to_owned)
            })
            .filter(|value| std::path::Path::new(value).is_absolute());
        let mut command = std::process::Command::new(executable);
        if let Some(resources) = resources {
            command.arg("--resources").arg(resources);
        }
        command.spawn().map(|_| ()).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        return Ok(());
    }
    #[cfg(not(target_os = "windows"))]
    {
        let _ = state;
        open_panel_window(
            &app,
            "emoji-panel",
            "emoji",
            "Emoji and more",
            720.0,
            720.0,
            None,
        )
    }
}

#[tauri::command]
fn close_panel(
    app: tauri::AppHandle,
    label: String,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    if !matches!(
        label.as_str(),
        "keyboard-panel" | "handwriting-panel" | "emoji-panel"
    ) {
        return Err(HostActionError {
            code: "invalid_panel",
        });
    }
    let result = app
        .get_webview_window(&label)
        .ok_or(HostActionError {
            code: "unavailable",
        })?
        .close()
        .map_err(|_| HostActionError {
            code: "unavailable",
        });
    if result.is_ok() && matches!(label.as_str(), "keyboard-panel" | "handwriting-panel") {
        if let Ok(mut target) = state.0.lock() {
            *target = None;
        }
    }
    result
}

fn clipboard_enabled(store: &std::sync::Arc<PreferencesStore>) -> Result<bool, HostActionError> {
    store
        .load()
        .map(|snapshot| snapshot.preferences.clipboard_history)
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn linux_clipboard_text() -> Result<String, HostActionError> {
    let output = std::process::Command::new("wl-paste")
        .arg("--no-newline")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .or_else(|| {
            std::process::Command::new("xclip")
                .args(["-selection", "clipboard", "-o"])
                .output()
                .ok()
                .filter(|output| output.status.success())
        })
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
    String::from_utf8(output.stdout)
        .map(|text| text.trim_end_matches(['\r', '\n']).to_owned())
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn write_linux_clipboard(text: &str) -> bool {
    fn write_with(mut child: std::process::Child, text: &str) -> bool {
        let Some(mut input) = child.stdin.take() else {
            return false;
        };
        if std::io::Write::write_all(&mut input, text.as_bytes()).is_err() {
            return false;
        }
        drop(input);
        child.wait().map(|status| status.success()).unwrap_or(false)
    }

    if let Ok(child) = std::process::Command::new("wl-copy")
        .stdin(std::process::Stdio::piped())
        .spawn()
    {
        if write_with(child, text) {
            return true;
        }
    }
    let Ok(child) = std::process::Command::new("xclip")
        .args(["-selection", "clipboard"])
        .stdin(std::process::Stdio::piped())
        .spawn()
    else {
        return false;
    };
    write_with(child, text)
}

#[cfg(target_os = "linux")]
fn start_linux_clipboard_monitor(
    history: Arc<Mutex<ClipboardHistoryStore>>,
    preferences: Arc<PreferencesStore>,
) {
    let _ = std::thread::Builder::new()
        .name("msime-clipboard-monitor".to_owned())
        .spawn(move || {
            let mut last_text = None;
            loop {
                let enabled = preferences
                    .load()
                    .map(|snapshot| snapshot.preferences.clipboard_history)
                    .unwrap_or(false);
                if !enabled {
                    last_text = None;
                } else if let Ok(text) = linux_clipboard_text() {
                    if last_text.as_deref() != Some(text.as_str()) {
                        if let Ok(mut store) = history.lock() {
                            let _ = store.push(text.clone());
                        }
                        last_text = Some(text);
                    }
                }
                std::thread::sleep(std::time::Duration::from_millis(750));
            }
        });
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
    let output = linux_clipboard_text();
    #[cfg(target_os = "windows")]
    let output = std::process::Command::new("powershell")
        .args(["-NoProfile", "-Command", "Get-Clipboard"])
        .output();
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    let output: Result<std::process::Output, std::io::Error> =
        Err(std::io::Error::other("unsupported"));
    #[cfg(target_os = "linux")]
    let text = output?;
    #[cfg(not(target_os = "linux"))]
    let text = {
        let output = output.map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        if !output.status.success() {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        String::from_utf8(output.stdout)
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .trim_end_matches(['\r', '\n'])
            .to_owned()
    };
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
    let result = write_linux_clipboard(&text);
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
            let preferences = Arc::new(PreferencesStore::new(&directory));
            app.manage(preferences.clone());
            #[cfg(target_os = "linux")]
            start_linux_preferences_monitor(app.handle(), preferences.clone());
            let clipboard_state = ClipboardHistoryState(Arc::new(Mutex::new(clipboard)));
            app.manage(ClipboardHistoryState(Arc::clone(&clipboard_state.0)));
            #[cfg(target_os = "linux")]
            start_linux_clipboard_monitor(Arc::clone(&clipboard_state.0), preferences);
            app.manage(PanelInputState::default());
            // Native packaging/installer supplies this verified HostOptions JSON.
            // Webview input never controls resource or state paths.
            let host_options_path = std::env::var_os("MSIME_CLIENT_HOST_OPTIONS")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .or_else(|| {
                    std::env::var_os("MSIME_IBUS_OPTIONS")
                        .map(PathBuf::from)
                        .filter(|path| path.is_absolute())
                })
                .ok_or_else(|| {
                    "MSIME_CLIENT_HOST_OPTIONS or MSIME_IBUS_OPTIONS must point to a prepared HostOptions JSON"
                        .to_string()
                })?;
            let host_options = fs::read_to_string(&host_options_path)
                .map_err(|_| "Cannot read prepared HostOptions JSON".to_string())?;
            let host_document: Value = serde_json::from_str(&host_options)
                .map_err(|_| "Cannot parse prepared HostOptions JSON".to_string())?;
            let runtime_path = std::env::var_os("MSIME_IBUS_OPTIONS")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .or_else(|| Some(host_options_path.clone()));
            app.manage(DictionaryHostOptions(Arc::new(host_options)));
            app.manage(RuntimeOptionsState {
                path: runtime_path,
                document: Arc::new(Mutex::new(host_document)),
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_preferences,
            save_preferences,
            list_clipboard_history,
            clear_clipboard_history,
            sync_clipboard_history,
            copy_text,
            remember_input_target,
            send_key,
            recognize_handwriting,
            submit_handwriting_candidate,
            open_external_url,
            open_keyboard_panel,
            open_handwriting_panel,
            open_emoji_panel,
            close_panel,
            dictionary_request,
            load_emoji_catalog
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "linux")]
    use super::*;

    #[cfg(target_os = "linux")]
    #[test]
    fn runtime_options_sync_replaces_preferences_atomically() {
        let directory = tempfile::tempdir().expect("temporary directory");
        let path = directory.path().join("runtime-options.json");
        let document = serde_json::json!({
            "api_version": 1,
            "resources": "/resources",
            "preferences": {"candidate_page_size": 5}
        });
        std::fs::write(&path, serde_json::to_vec(&document).unwrap()).unwrap();
        let state = RuntimeOptionsState {
            path: Some(path.clone()),
            document: Arc::new(Mutex::new(document)),
        };
        let mut preferences = Preferences::default();
        preferences.candidate_page_size = 9;
        sync_linux_runtime_options(&state, &preferences).unwrap();
        let updated: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!(updated["preferences"]["candidate_page_size"], 9);
    }
}

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
#[cfg(all(not(target_os = "windows"), not(mobile)))]
use tauri::{WebviewUrl, WebviewWindowBuilder};

mod skin_directory;

struct ClipboardHistoryState(Arc<Mutex<ClipboardHistoryStore>>);
struct DictionaryHostOptions(Arc<String>);
struct SkinDirectoryState(PathBuf);

fn read_skin_toolbar_stylesheet_at(
    root: PathBuf,
    id: &str,
) -> Result<Option<String>, CommandError> {
    msime_client_core::skin_catalog::read_toolbar_stylesheet(root, id)
        .map_err(|_| CommandError { code: "storage" })
}

#[tauri::command]
async fn read_skin_toolbar_stylesheet(
    directory: tauri::State<'_, SkinDirectoryState>,
    id: String,
) -> Result<Option<String>, CommandError> {
    let root = directory.0.clone();
    tauri::async_runtime::spawn_blocking(move || read_skin_toolbar_stylesheet_at(root, &id))
        .await
        .map_err(|_| CommandError { code: "storage" })?
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct SkinImageResponse {
    content_type: &'static str,
    bytes: Vec<u8>,
}

fn read_skin_image_at(
    root: PathBuf,
    id: &str,
    relative: &str,
) -> Result<SkinImageResponse, CommandError> {
    let resource = msime_client_core::skin_catalog::read_resource(root, id, relative)
        .map_err(|_| CommandError { code: "storage" })?;
    if !resource.content_type.starts_with("image/") {
        return Err(CommandError {
            code: "invalid_resource",
        });
    }
    Ok(SkinImageResponse {
        content_type: resource.content_type,
        bytes: resource.bytes,
    })
}

#[tauri::command]
async fn read_skin_image(
    directory: tauri::State<'_, SkinDirectoryState>,
    id: String,
    relative: String,
) -> Result<SkinImageResponse, CommandError> {
    let root = directory.0.clone();
    tauri::async_runtime::spawn_blocking(move || read_skin_image_at(root, &id, &relative))
        .await
        .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn open_skin_directory(
    directory: tauri::State<'_, SkinDirectoryState>,
) -> Result<(), CommandError> {
    let root = directory.0.clone();
    tauri::async_runtime::spawn_blocking(move || skin_directory::open(&root))
        .await
        .map_err(|_| CommandError { code: "storage" })?
        .map_err(|code| CommandError { code })
}

#[derive(serde::Serialize)]
struct SkinCatalogResponse {
    directory: String,
    #[serde(flatten)]
    catalog: msime_client_core::skin_catalog::SkinCatalog,
}

fn read_skin_catalog(root: PathBuf) -> SkinCatalogResponse {
    SkinCatalogResponse {
        directory: root.to_string_lossy().into_owned(),
        catalog: msime_client_core::skin_catalog::scan(root),
    }
}

#[tauri::command]
async fn scan_skin_catalog(
    directory: tauri::State<'_, SkinDirectoryState>,
) -> Result<SkinCatalogResponse, CommandError> {
    // The host chooses the root; the webview cannot request arbitrary folders.
    let root = directory.0.clone();
    tauri::async_runtime::spawn_blocking(move || read_skin_catalog(root))
        .await
        .map_err(|_| CommandError { code: "storage" })
}

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
    Ydotool,
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

#[tauri::command]
async fn cloud_clipboard_request(
    options: tauri::State<'_, DictionaryHostOptions>,
    action: Value,
) -> Result<Value, CommandError> {
    msime_host_api::cloud_clipboard::validate_request(&action)
        .map_err(|_| CommandError { code: "invalid" })?;
    let options = options.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(unix)]
        {
            let configured = serde_json::from_str::<Value>(&options)
                .ok()
                .and_then(|value| {
                    value
                        .get("cloud_clipboard_provider_socket")
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                });
            let path = configured
                .or_else(|| {
                    std::env::var_os("MSIME_CLOUD_CLIPBOARD_PROVIDER_SOCKET")
                        .and_then(|value| value.into_string().ok())
                })
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .ok_or(CommandError {
                    code: "unavailable",
                })?;
            return UnixSocketProvider::new(path)
                .cloud_clipboard(action)
                .ok_or(CommandError {
                    code: "unavailable",
                });
        }
        #[cfg(not(unix))]
        {
            let _ = (options, action);
            Err(CommandError {
                code: "unavailable",
            })
        }
    })
    .await
    .map_err(|_| CommandError {
        code: "unavailable",
    })?
}

#[tauri::command]
async fn cloud_dictionary_request(
    options: tauri::State<'_, DictionaryHostOptions>,
    action: Value,
) -> Result<Value, CommandError> {
    let request =
        serde_json::from_value::<msime_host_api::cloud_dictionary::CloudDictionaryRequest>(
            action.clone(),
        )
        .map_err(|_| CommandError { code: "invalid" })?;
    msime_host_api::cloud_dictionary::validate_cloud_request(&request)
        .map_err(|_| CommandError { code: "invalid" })?;
    let options = options.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(unix)]
        {
            let configured = serde_json::from_str::<Value>(&options)
                .ok()
                .and_then(|value| {
                    value
                        .get("cloud_dictionary_provider_socket")
                        .and_then(Value::as_str)
                        .map(str::to_owned)
                });
            let path = configured
                .or_else(|| {
                    std::env::var_os("MSIME_CLOUD_DICTIONARY_PROVIDER_SOCKET")
                        .and_then(|value| value.into_string().ok())
                })
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .ok_or(CommandError {
                    code: "unavailable",
                })?;
            return UnixSocketProvider::new(path)
                .cloud_dictionary(action)
                .ok_or(CommandError {
                    code: "unavailable",
                });
        }
        #[cfg(not(unix))]
        {
            let _ = (options, action);
            Err(CommandError {
                code: "unavailable",
            })
        }
    })
    .await
    .map_err(|_| CommandError {
        code: "unavailable",
    })?
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
    let y = (rect.1 + rect.3 + 16.0).max(0.0);
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
        let ydotool_ready = std::process::Command::new("ydotool")
            .args(["type", "--key-delay", "0", ""])
            .output()
            .ok()
            .is_some_and(|output| output.status.success());
        if ydotool_ready {
            return Ok(PanelInputTarget::Ydotool);
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
fn ydotool_key_code(virtual_key: u16) -> Option<u16> {
    let code = match virtual_key {
        0x08 => 14,
        0x09 => 15,
        0x0d => 28,
        0x20 => 57,
        0x2e => 111,
        0x14 => 58,
        0xc0 => 41,
        0xbd => 12,
        0xbb => 13,
        0xdb => 26,
        0xdd => 27,
        0xdc => 43,
        0xba => 39,
        0xde => 40,
        0xbc => 51,
        0xbe => 52,
        0xbf => 53,
        0x30 => 11,
        0x31 => 2,
        0x32 => 3,
        0x33 => 4,
        0x34 => 5,
        0x35 => 6,
        0x36 => 7,
        0x37 => 8,
        0x38 => 9,
        0x39 => 10,
        0x41 => 30,
        0x42 => 48,
        0x43 => 46,
        0x44 => 32,
        0x45 => 18,
        0x46 => 33,
        0x47 => 34,
        0x48 => 35,
        0x49 => 23,
        0x4a => 36,
        0x4b => 37,
        0x4c => 38,
        0x4d => 50,
        0x4e => 49,
        0x4f => 24,
        0x50 => 25,
        0x51 => 16,
        0x52 => 19,
        0x53 => 31,
        0x54 => 20,
        0x55 => 22,
        0x56 => 47,
        0x57 => 17,
        0x58 => 45,
        0x59 => 21,
        0x5a => 44,
        _ => return None,
    };
    Some(code)
}

#[cfg(target_os = "linux")]
fn run_ydotool(args: &[String]) -> Result<(), HostActionError> {
    std::process::Command::new("ydotool")
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
    if matches!(target, PanelInputTarget::Ydotool) {
        return run_ydotool(args);
    }
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
fn hide_linux_panels(app: &tauri::AppHandle) {
    for label in [
        "keyboard-panel",
        "handwriting-panel",
        "emoji-panel",
        "voice-panel",
        "cloud-clipboard-panel",
        "cloud-dictionary-panel",
    ] {
        if let Some(window) = app.get_webview_window(label) {
            let _ = window.hide();
        }
    }
}

#[cfg(target_os = "linux")]
fn send_panel_key(
    app: &tauri::AppHandle,
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
    if let PanelInputTarget::Ydotool = target {
        let code = ydotool_key_code(request.virtual_key).ok_or(HostActionError {
            code: "invalid_key",
        })?;
        let mut args = Vec::new();
        let mut modifiers = Vec::new();
        if request.include_sticky_modifiers {
            if request.modifiers.ctrl {
                modifiers.push(29u16);
            }
            if request.modifiers.alt {
                modifiers.push(56u16);
            }
            if request.modifiers.win {
                modifiers.push(125u16);
            }
        }
        for modifier in &modifiers {
            args.push(format!("{modifier}:1"));
        }
        if request.shift {
            args.push("42:1".to_owned());
        }
        args.push(format!("{code}:1"));
        args.push(format!("{code}:0"));
        if request.shift {
            args.push("42:0".to_owned());
        }
        for modifier in modifiers.iter().rev() {
            args.push(format!("{modifier}:0"));
        }
        let mut command_args = Vec::with_capacity(args.len() + 1);
        command_args.push("key".to_owned());
        command_args.extend(args);
        return run_ydotool(&command_args);
    }
    let key = xdotool_key_name(request.virtual_key).ok_or(HostActionError {
        code: "invalid_key",
    })?;
    if matches!(target, PanelInputTarget::Wayland) {
        hide_linux_panels(app);
    }
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
    app: &tauri::AppHandle,
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
    if let PanelInputTarget::Ydotool = target {
        return run_ydotool(&[
            "type".to_owned(),
            "--key-delay".to_owned(),
            "0".to_owned(),
            text.to_owned(),
        ]);
    }
    if matches!(target, PanelInputTarget::Wayland) {
        hide_linux_panels(app);
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
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return send_panel_key(&app, &state, request);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, request);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn recognize_handwriting(
    request: HandwritingRecognitionRequest,
    options: tauri::State<'_, DictionaryHostOptions>,
) -> Result<HandwritingRecognitionResult, HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_stroke",
    })?;
    #[cfg(unix)]
    {
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
        let path = std::env::var_os("MSIME_HANDWRITING_PROVIDER_SOCKET")
            .map(std::path::PathBuf::from)
            .filter(|path| path.is_absolute())
            .map(|path| (path, true));
        let configured = serde_json::from_str::<Value>(&options.0)
            .ok()
            .and_then(|value| {
                value
                    .get("handwriting_model")
                    .and_then(Value::as_str)
                    .map(str::to_owned)
            })
            .map(std::path::PathBuf::from)
            .filter(|path| path.is_absolute());
        let model = configured
            .or_else(|| std::env::var_os("MSIME_HANDWRITING_MODEL").map(std::path::PathBuf::from))
            .or_else(|| {
                std::env::current_exe().ok().and_then(|exe| {
                    exe.parent()?.parent().map(|prefix| {
                        prefix.join("share/msime-client/handwriting/handwriting-zh_CN.model")
                    })
                })
            })
            .filter(|path| path.is_absolute() && path.is_file());
        let candidates = if let Some((path, _)) = path {
            tauri::async_runtime::spawn_blocking(move || {
                UnixSocketProvider::new(path).handwriting(query)
            })
            .await
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .ok_or(HostActionError {
                code: "unavailable",
            })?
        } else if let Some(model) = model {
            tauri::async_runtime::spawn_blocking(move || {
                msime_host_api::handwriting_local_candidates(
                    model.to_str().unwrap_or_default(),
                    &query,
                )
            })
            .await
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
        } else {
            return Err(HostActionError {
                code: "unavailable",
            });
        };
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

#[derive(serde::Deserialize)]
struct VoiceRecognitionRequest {
    language: String,
}

#[derive(serde::Serialize)]
struct VoiceRecognitionResult {
    text: String,
}

fn voice_provider_options(document: &Value) -> Value {
    let Some(voice) = document
        .get("preferences")
        .and_then(|value| value.get("voice_input"))
        .and_then(Value::as_object)
    else {
        return Value::Object(Default::default());
    };
    let mut options = serde_json::Map::new();
    for key in [
        "sound_enabled",
        "start_sound",
        "end_sound",
        "mute_system_audio",
        "polish_enabled",
        "polish_text",
        "doubao_enable_itn",
        "doubao_enable_punc",
        "doubao_enable_ddc",
    ] {
        if let Some(value) = voice.get(key).filter(|value| value.is_boolean()) {
            options.insert(key.to_owned(), value.clone());
        }
    }
    for key in [
        "commit_mode",
        "asr_provider",
        "asr_endpoint",
        "asr_model",
        "polish_provider",
        "polish_endpoint",
        "polish_model",
        "polish_prompt_id",
    ] {
        if let Some(value) = voice.get(key).and_then(Value::as_str) {
            let bounded = value.chars().take(512).collect::<String>();
            options.insert(key.to_owned(), Value::String(bounded));
        }
    }
    Value::Object(options)
}

#[tauri::command]
async fn recognize_voice(
    request: VoiceRecognitionRequest,
    options: tauri::State<'_, DictionaryHostOptions>,
) -> Result<VoiceRecognitionResult, HostActionError> {
    if request.language.is_empty()
        || request.language.len() > 64
        || request.language.chars().any(char::is_control)
    {
        return Err(HostActionError {
            code: "invalid_voice",
        });
    }
    #[cfg(unix)]
    {
        let document = serde_json::from_str::<Value>(&options.0).unwrap_or(Value::Null);
        let provider_options = voice_provider_options(&document);
        let configured = serde_json::from_str::<serde_json::Value>(&options.0)
            .ok()
            .and_then(|value| {
                value
                    .get("voice_provider_socket")
                    .and_then(serde_json::Value::as_str)
                    .map(str::to_owned)
            });
        let path = configured
            .or_else(|| {
                std::env::var_os("MSIME_VOICE_PROVIDER_SOCKET")
                    .and_then(|value| value.into_string().ok())
            })
            .map(std::path::PathBuf::from)
            .filter(|path| path.is_absolute())
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        let language = request.language;
        let text = tauri::async_runtime::spawn_blocking(move || {
            UnixSocketProvider::new(path).voice_with_options(&language, 1, &provider_options)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
        return Ok(VoiceRecognitionResult { text });
    }
    #[cfg(not(unix))]
    {
        let _ = (request, options);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn submit_handwriting_candidate(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    candidate: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return send_panel_text(&app, &state, &candidate);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, candidate);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn send_text(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    text: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return send_panel_text(&app, &state, &text);
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, text);
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
    #[cfg(mobile)]
    {
        let _ = (app, label, route, title, width, height, position);
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(not(mobile))]
    {
        if let Some(window) = app.get_webview_window(label) {
            #[cfg(target_os = "linux")]
            if let Some((x, y)) = position {
                let _ = window.set_position(tauri::Position::Physical(
                    tauri::PhysicalPosition::new(x.round() as i32, y.round() as i32),
                ));
            }
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
    options: tauri::State<'_, DictionaryHostOptions>,
    input: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, input);
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
        let resources = serde_json::from_str::<serde_json::Value>(&options.0)
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
        #[cfg(not(target_os = "linux"))]
        let _ = (&options, &input);
        #[cfg(target_os = "linux")]
        let position = {
            let _ = &options;
            let _ = remember_panel_input_target(&input, true);
            panel_position(&input, 720.0, 720.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "emoji-panel",
            "emoji",
            "Emoji and more",
            720.0,
            720.0,
            position,
        )
    }
}

#[tauri::command]
fn open_voice_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, state);
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 620.0, 520.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "voice-panel",
            "voice",
            "水杉语音输入",
            620.0,
            520.0,
            position,
        )
    }
}

#[tauri::command]
fn open_cloud_clipboard_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, state);
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 560.0, 560.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "cloud-clipboard-panel",
            "cloud-clipboard",
            "水杉云剪贴板",
            560.0,
            560.0,
            position,
        )
    }
}

#[tauri::command]
fn open_cloud_dictionary_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = (app, state);
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(not(target_os = "windows"))]
    {
        #[cfg(not(target_os = "linux"))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 760.0, 700.0)
        };
        #[cfg(not(target_os = "linux"))]
        let position = None;
        open_panel_window(
            &app,
            "cloud-dictionary-panel",
            "cloud-dictionary",
            "水杉云词典",
            760.0,
            700.0,
            position,
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
        "keyboard-panel"
            | "handwriting-panel"
            | "emoji-panel"
            | "voice-panel"
            | "cloud-clipboard-panel"
            | "cloud-dictionary-panel"
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
    if result.is_ok()
        && matches!(
            label.as_str(),
            "keyboard-panel"
                | "handwriting-panel"
                | "voice-panel"
                | "cloud-clipboard-panel"
                | "cloud-dictionary-panel"
        )
    {
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
            app.manage(SkinDirectoryState(directory.join("skins")));
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
            #[cfg(target_os = "linux")]
            if let Ok(panel) = std::env::var("MSIME_CLIENT_PANEL") {
                let route = match panel.as_str() {
                    "keyboard" => Some((
                        "keyboard-panel",
                        "keyboard",
                        "水杉屏幕键盘",
                        1100.0,
                        400.0,
                    )),
                    "handwriting" => Some((
                        "handwriting-panel",
                        "handwriting",
                        "水杉手写识别板",
                        980.0,
                        650.0,
                    )),
                    "emoji" => Some((
                        "emoji-panel",
                        "emoji",
                        "Emoji and more",
                        720.0,
                        720.0,
                    )),
                    "voice" => Some((
                        "voice-panel",
                        "voice",
                        "水杉语音输入",
                        620.0,
                        520.0,
                    )),
                    "cloud-clipboard" => Some((
                        "cloud-clipboard-panel",
                        "cloud-clipboard",
                        "水杉云剪贴板",
                        560.0,
                        560.0,
                    )),
                    "cloud-dictionary" => Some((
                        "cloud-dictionary-panel",
                        "cloud-dictionary",
                        "水杉云词典",
                        760.0,
                        700.0,
                    )),
                    _ => None,
                };
                if let Some((label, route, title, width, height)) = route {
                    // The property-menu process is the panel launcher in this
                    // path, so capture the foreground editor before the new
                    // window can take focus. This is the same handoff used by
                    // the settings-page panel commands.
                    let panel_input = app.state::<PanelInputState>();
                    let _ = remember_panel_input_target(panel_input.inner(), true);
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.hide();
                    }
                    open_panel_window(
                        app.handle(), label, route, title, width, height, None,
                    )
                    .map_err(|_| "Cannot open requested panel".to_string())?;
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            load_preferences,
            scan_skin_catalog,
            read_skin_image,
            read_skin_toolbar_stylesheet,
            open_skin_directory,
            save_preferences,
            list_clipboard_history,
            clear_clipboard_history,
            sync_clipboard_history,
            copy_text,
            remember_input_target,
            send_key,
            send_text,
            recognize_handwriting,
            recognize_voice,
            submit_handwriting_candidate,
            open_external_url,
            open_keyboard_panel,
            open_handwriting_panel,
            open_emoji_panel,
            open_voice_panel,
            open_cloud_clipboard_panel,
            open_cloud_dictionary_panel,
            close_panel,
            dictionary_request,
            cloud_clipboard_request,
            cloud_dictionary_request,
            load_emoji_catalog
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

#[cfg(test)]
mod tests {
    #[test]
    fn toolbar_stylesheet_command_errors_do_not_expose_paths() {
        let state = tempfile::tempdir().unwrap();
        let result =
            super::read_skin_toolbar_stylesheet_at(state.path().join("skins"), "../sample");
        let error = match result {
            Err(error) => error,
            Ok(_) => panic!("expected error"),
        };
        assert_eq!(
            serde_json::to_value(error).unwrap(),
            serde_json::json!({ "code": "storage" })
        );
    }
    #[test]
    fn skin_image_command_contract_filters_non_images_and_paths() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        let folder = root.join("sample");
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(folder.join("skin.toml"), "schema_version = 1\nid = 'sample'\nname = 'Sample'\nversion = '1'\nbase = 'fluent'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n[candidate_window]\n[candidate_window.decoration]\n").unwrap();
        std::fs::write(folder.join("preview.png"), [0, 1, 255]).unwrap();
        std::fs::write(folder.join("toolbar.css"), b".sample {}").unwrap();
        assert!(matches!(
            super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"),
            Ok(None)
        ));
        let manifest = std::fs::read_to_string(folder.join("skin.toml")).unwrap();
        std::fs::write(
            folder.join("skin.toml"),
            format!("toolbar_stylesheet = 'toolbar.css'\n{manifest}"),
        )
        .unwrap();
        assert!(
            matches!(super::read_skin_toolbar_stylesheet_at(root.clone(), "sample"), Ok(Some(css)) if css == ".sample {}")
        );
        let result = super::read_skin_image_at(root.clone(), "sample", "preview.png")
            .ok()
            .unwrap();
        let json = serde_json::to_value(result).unwrap();
        assert_eq!(json["contentType"], "image/png");
        assert_eq!(json["bytes"], serde_json::json!([0, 1, 255]));
        assert!(super::read_skin_image_at(root.clone(), "sample", "toolbar.css").is_err());
        assert!(super::read_skin_image_at(root.clone(), "sample", "../preview.png").is_err());
        assert!(super::read_skin_image_at(root, "../sample", "preview.png").is_err());
    }

    #[test]
    fn skin_catalog_response_uses_host_root_and_preserves_scan_results() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        let folder = root.join("sample");
        std::fs::create_dir_all(&folder).unwrap();
        std::fs::write(
            folder.join("skin.toml"),
            r#"schema_version = 1
id = 'sample'
name = 'Sample'
version = '1'
base = 'fluent'
[supports]
layouts = ['vertical']
themes = ['light']
[candidate_window]
[candidate_window.decoration]
"#,
        )
        .unwrap();
        std::fs::create_dir(root.join("Bad")).unwrap();
        let result = serde_json::to_value(super::read_skin_catalog(root.clone())).unwrap();
        assert_eq!(result["directory"], root.to_string_lossy().as_ref());
        assert_eq!(result["packages"][0]["id"], "sample");
        assert_eq!(result["packages"].as_array().unwrap().len(), 1);
        assert_eq!(result["issues"].as_array().unwrap().len(), 1);
        assert_eq!(
            result["packages"][0]["layouts"],
            serde_json::json!(["vertical"])
        );
        assert_eq!(result["issues"][0]["folder"], "Bad");
        assert!(result.get("catalog").is_none());
    }

    #[test]
    fn scanning_missing_skin_directory_does_not_create_it() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        let result = super::read_skin_catalog(root.clone());
        assert!(result.catalog.packages.is_empty());
        assert!(result.catalog.issues.is_empty());
        assert!(!root.exists());
    }

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

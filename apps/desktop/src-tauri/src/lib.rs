#[cfg(target_os = "linux")]
mod linux_process;
#[cfg(target_os = "linux")]
mod linux_audio_devices;
#[cfg(target_os = "linux")]
mod linux_clipboard;

use msime_client_core::clipboard::ClipboardHistoryStore;
use msime_client_core::custom_skin_library::{
    CustomSkinLibraryAction, CustomSkinLibraryError, CustomSkinLibraryStore,
    SavedTouchKeyboardSkin,
};
use msime_client_core::panels::{
    HandwritingRecognitionRequest, HandwritingRecognitionResult, KeyboardInputRequest,
};
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use msime_client_core::typing_statistics::{TypingStatistics, TypingStatisticsStore};
// The packaged recognizer runs on every host; only the socket provider is unix.
#[cfg(unix)]
use msime_input_runtime::UnixSocketProvider;
use msime_input_runtime::{HandwritingPoint, HandwritingQuery};
use serde_json::Value;
#[cfg(unix)]
use std::collections::HashMap;
use std::fs;
#[cfg(target_os = "linux")]
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::FileTypeExt;
#[cfg(target_os = "linux")]
use std::path::Path;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
#[cfg(unix)]
use tauri::Emitter;
use tauri::Manager;
#[cfg(not(mobile))]
use tauri::{WebviewUrl, WebviewWindowBuilder};

mod skin_directory;
#[cfg(unix)]
mod voice_sessions;
use msime_host_api::system_fonts;

#[tauri::command]
fn supports_font_catalog() -> bool {
    system_fonts::supported()
}

/// The settings section a host menu asked for, if any. The launcher passes it
/// in the environment, like the panel routes; the settings page falls back to
/// its own default when this is absent or unusable.
#[tauri::command]
fn initial_settings_page() -> Option<String> {
    requested_settings_page(std::env::var("MSIME_CLIENT_SETTINGS_PAGE").ok().as_deref())
}

fn requested_settings_page(value: Option<&str>) -> Option<String> {
    // Only a short identifier is accepted here; the page list itself lives in
    // the shared settings UI, which refuses ids it does not have.
    value
        .map(str::trim)
        .filter(|page| {
            !page.is_empty()
                && page.len() <= 32
                && page
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte == b'-')
        })
        .map(str::to_owned)
}

#[tauri::command]
async fn list_font_families() -> Result<Vec<String>, CommandError> {
    tauri::async_runtime::spawn_blocking(system_fonts::list)
        .await
        .map_err(|_| CommandError {
            code: "font_catalog",
        })?
        .map_err(|code| CommandError { code })
}

#[tauri::command]
async fn list_voice_capture_devices() -> Result<Value, CommandError> {
    #[cfg(target_os = "linux")]
    {
        let devices = tauri::async_runtime::spawn_blocking(linux_audio_devices::list)
            .await.map_err(|_| CommandError { code: "audio_devices" })?;
        serde_json::to_value(devices).map_err(|_| CommandError { code: "audio_devices" })
    }
    #[cfg(not(target_os = "linux"))]
    Err(CommandError { code: "unavailable" })
}

#[derive(Clone)]
struct ClipboardHistoryState(Arc<Mutex<ClipboardHistoryStore>>);
#[derive(Clone)]
struct DictionaryHostOptions {
    #[cfg(target_os = "linux")]
    path: PathBuf,
    #[cfg(not(target_os = "linux"))]
    document: Arc<Value>,
}

impl DictionaryHostOptions {
    fn snapshot(&self) -> Result<Value, CommandError> {
        #[cfg(target_os = "linux")]
        {
            // Keep the installer-selected path separate from the IBus runtime
            // path; deployments can supply different files for these roles.
            read_runtime_options(&self.path).map_err(|_| CommandError { code: "storage" })
        }
        #[cfg(not(target_os = "linux"))]
        {
            Ok((*self.document).clone())
        }
    }
}

struct SkinDirectoryState(PathBuf);
struct TypingStatisticsState(TypingStatisticsStore);

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct TypingStatisticsStatus {
    statistics: TypingStatistics,
    availability: &'static str,
    last_written_ms: Option<u64>,
}

fn typing_statistics_status(
    store: &TypingStatisticsStore,
    statistics: TypingStatistics,
) -> Result<TypingStatisticsStatus, CommandError> {
    let last_written = store
        .last_written()
        .map_err(|_| CommandError { code: "storage" })?;
    Ok(TypingStatisticsStatus {
        statistics,
        availability: if last_written.is_some() {
            "ready"
        } else {
            "neverWritten"
        },
        last_written_ms: last_written.and_then(|time| {
            time.duration_since(std::time::UNIX_EPOCH)
                .ok()
                .map(|duration| u64::try_from(duration.as_millis()).unwrap_or(u64::MAX))
        }),
    })
}

#[tauri::command]
async fn load_typing_statistics(
    state: tauri::State<'_, TypingStatisticsState>,
) -> Result<TypingStatisticsStatus, CommandError> {
    let store = state.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let statistics = store.load().map_err(|_| CommandError { code: "storage" })?;
        typing_statistics_status(&store, statistics)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn set_typing_statistics_enabled(
    state: tauri::State<'_, TypingStatisticsState>,
    enabled: bool,
) -> Result<TypingStatisticsStatus, CommandError> {
    let store = state.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let statistics = store
            .set_enabled(enabled)
            .map_err(|_| CommandError { code: "storage" })?;
        typing_statistics_status(&store, statistics)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn reset_typing_statistics(
    state: tauri::State<'_, TypingStatisticsState>,
) -> Result<TypingStatisticsStatus, CommandError> {
    let store = state.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let statistics = store
            .reset()
            .map_err(|_| CommandError { code: "storage" })?;
        typing_statistics_status(&store, statistics)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

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

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct SkinFontResponse {
    content_type: &'static str,
    bytes: Vec<u8>,
}

fn read_skin_font_at(
    root: PathBuf,
    id: &str,
    relative: &str,
) -> Result<SkinFontResponse, CommandError> {
    let resource = msime_client_core::skin_catalog::read_resource(root, id, relative)
        .map_err(|_| CommandError { code: "storage" })?;
    if !resource.content_type.starts_with("font/") {
        return Err(CommandError {
            code: "invalid_resource",
        });
    }
    Ok(SkinFontResponse {
        content_type: resource.content_type,
        bytes: resource.bytes,
    })
}

#[tauri::command]
async fn read_skin_font(
    directory: tauri::State<'_, SkinDirectoryState>,
    id: String,
    relative: String,
) -> Result<SkinFontResponse, CommandError> {
    let root = directory.0.clone();
    tauri::async_runtime::spawn_blocking(move || read_skin_font_at(root, &id, &relative))
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

#[cfg(unix)]
impl RuntimeOptionsState {
    fn snapshot(&self) -> Result<Value, std::io::Error> {
        let document = self
            .document
            .lock()
            .map_err(|_| std::io::Error::other("runtime options lock poisoned"))?;
        #[cfg(target_os = "linux")]
        let mut document = document;
        #[cfg(target_os = "linux")]
        if let Some(path) = self.path.as_ref() {
            *document = read_runtime_options(path)?;
        }
        Ok(document.clone())
    }
}

#[cfg(target_os = "linux")]
fn read_runtime_options(path: &Path) -> Result<Value, std::io::Error> {
    let document: Value = serde_json::from_slice(&fs::read(path)?)
        .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
    if !document.is_object() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::InvalidData,
            "runtime options must be an object",
        ));
    }
    Ok(document)
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

// The window that owned the caret before the panel appeared. Panels never take
// focus, but a click still has to reach that window and not the panel itself.
#[cfg(target_os = "windows")]
#[derive(Clone, Copy, Debug)]
struct PanelInputTarget(msime_host_windows::InputTarget);

#[cfg(not(any(target_os = "linux", target_os = "windows")))]
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

fn custom_skin_library_error(value: CustomSkinLibraryError) -> CommandError {
    CommandError {
        code: match value {
            CustomSkinLibraryError::Full => "custom_skin_full",
            CustomSkinLibraryError::InvalidName => "custom_skin_invalid_name",
            CustomSkinLibraryError::DuplicateName => "custom_skin_duplicate_name",
            CustomSkinLibraryError::NotFound => "custom_skin_not_found",
            CustomSkinLibraryError::Json(_) | CustomSkinLibraryError::Invalid => {
                "custom_skin_format"
            }
            CustomSkinLibraryError::Io(_) => "storage",
        },
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
        if !snapshot.preferences.clipboard_history {
            store.clear_disabled_clipboard_history().map_err(CommandError::from)?;
        }
        sync_linux_runtime_options(&runtime, &snapshot.preferences)
            .map_err(|_| CommandError { code: "storage" })?;
        Ok(snapshot)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn load_custom_skin_library(
    store: tauri::State<'_, CustomSkinLibraryStore>,
) -> Result<Vec<SavedTouchKeyboardSkin>, CommandError> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        store.load().map_err(custom_skin_library_error)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[tauri::command]
async fn mutate_custom_skin_library(
    store: tauri::State<'_, CustomSkinLibraryStore>,
    action: CustomSkinLibraryAction,
) -> Result<Vec<SavedTouchKeyboardSkin>, CommandError> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        store.mutate(action).map_err(custom_skin_library_error)
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
        // Another settings process or the host may have updated endpoints and
        // resource paths since this panel started. Preserve that document.
        let mut current = read_runtime_options(path)?;
        current["preferences"] = serde_json::to_value(preferences)
            .map_err(|error| std::io::Error::other(error.to_string()))?;
        let bytes = serde_json::to_vec_pretty(&current)
            .map_err(|error| std::io::Error::other(error.to_string()))?;
        atomic_write(path, &bytes)?;
        *document = current;
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
    history: Arc<Mutex<ClipboardHistoryStore>>,
) {
    let app = app.clone();
    let _ = std::thread::Builder::new()
        .name("msime-preferences-monitor".to_owned())
        .spawn(move || {
            let mut revision = store.load().ok().map(|snapshot| snapshot.revision);
            let mut last_history: Option<Vec<String>> = None;
            loop {
                std::thread::sleep(std::time::Duration::from_millis(750));
                let Ok(snapshot) = store.load() else {
                    continue;
                };
                let entries = if snapshot.preferences.clipboard_history {
                    history.lock().ok().and_then(|mut history| {
                        history.load().ok().map(|_| history.entries().to_vec())
                    })
                } else {
                    Some(Vec::new())
                };
                if let Some(entries) = entries {
                    if last_history.as_ref() != Some(&entries) {
                        last_history = Some(entries);
                        // Only invalidate the view; clipboard text stays out of events.
                        let _ = app.emit("clipboard-history-changed", ());
                    }
                }
                if revision != Some(snapshot.revision) {
                    revision = Some(snapshot.revision);
                    let _ = app.emit("preferences-changed", snapshot);
                }
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
    let options = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let options = options.snapshot()?;
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
    let options = options.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(unix)]
        {
            let document = options.snapshot()?;
            let configured = document
                .get("cloud_clipboard_provider_socket")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let path = configured
                .or_else(|| {
                    std::env::var_os("MSIME_CLOUD_CLIPBOARD_PROVIDER_SOCKET")
                        .and_then(|value| value.into_string().ok())
                })
                .map(PathBuf::from)
                .or_else(|| discover_session_provider("cloud-clipboard.sock"))
                .filter(|path| path.is_absolute())
                .ok_or(CommandError {
                    code: "unavailable",
                })?;
            UnixSocketProvider::new(path)
                .cloud_clipboard(action)
                .ok_or(CommandError {
                    code: "unavailable",
                })
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
    let options = options.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(unix)]
        {
            let document = options.snapshot()?;
            let configured = document
                .get("cloud_dictionary_provider_socket")
                .and_then(Value::as_str)
                .map(str::to_owned);
            let path = configured
                .or_else(|| {
                    std::env::var_os("MSIME_CLOUD_DICTIONARY_PROVIDER_SOCKET")
                        .and_then(|value| value.into_string().ok())
                })
                .map(PathBuf::from)
                .or_else(|| discover_session_provider("cloud-dictionary.sock"))
                .filter(|path| path.is_absolute())
                .ok_or(CommandError {
                    code: "unavailable",
                })?;
            UnixSocketProvider::new(path)
                .cloud_dictionary(action)
                .ok_or(CommandError {
                    code: "unavailable",
                })
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
    #[serde(skip_serializing_if = "Option::is_none")]
    parent: Option<String>,
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
    if category == "symbols" {
        return msime_host_api::local_symbol_catalog(resources).map(|groups| {
            groups
                .into_iter()
                .map(|group| EmojiCatalogGroup {
                    title: group.title,
                    parent: Some(group.parent),
                    icon: group
                        .items
                        .first()
                        .map(|item| item.text.clone())
                        .unwrap_or_default(),
                    items: group
                        .items
                        .into_iter()
                        .map(|item| EmojiCatalogItem {
                            keywords: if item.annotation.is_empty() {
                                item.group
                            } else {
                                item.annotation
                            },
                            text: item.text,
                        })
                        .collect(),
                })
                .filter(|group| !group.items.is_empty())
                .collect()
        });
    }
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
                    parent: None,
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
    let options = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let document = options.snapshot()?;
        #[cfg(target_os = "linux")]
        let resource_directory = packaged_emoji_resources(&document)
            .ok_or(CommandError { code: "unavailable" })?;
        #[cfg(target_os = "linux")]
        let resources = resource_directory
            .to_str()
            .ok_or(CommandError { code: "storage" })?;
        #[cfg(not(target_os = "linux"))]
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

#[tauri::command]
fn restart_input_method() -> Result<(), HostActionError> {
    #[cfg(not(target_os = "linux"))]
    {
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(target_os = "linux")]
    {
        let status = std::process::Command::new("ibus")
            .arg("restart")
            .status()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        status.success().then_some(()).ok_or(HostActionError {
            code: "unavailable",
        })
    }
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
    let read = |program: &str, arguments: &[&str], limit: usize| {
        linux_process::read_text(program, arguments, limit, std::time::Duration::from_secs(1))
    };
    let sway_target = || {
        let output = read("swaymsg", &["-t", "get_tree", "-r"], 1024 * 1024)?;
        let tree: serde_json::Value = serde_json::from_str(&output).ok()?;
        focused_sway_container(&tree).map(PanelInputTarget::Sway)
    };
    let wayland_session = std::env::var_os("WAYLAND_DISPLAY").is_some()
        || std::env::var("XDG_SESSION_TYPE").as_deref() == Ok("wayland");
    if wayland_session {
        if let Some(target) = sway_target() {
            return Ok(target);
        }
        if read("ydotool", &["type", "--key-delay", "0", ""], 4096).is_some() {
            return Ok(PanelInputTarget::Ydotool);
        }
        // wtype has no --version option. Empty stdin checks the compositor's
        // virtual-keyboard support without emitting any text or key events.
        if read("wtype", &["-"], 4096).is_some() {
            return Ok(PanelInputTarget::Wayland);
        }
    }
    if let Some(output) = read("xdotool", &["getactivewindow"], 64) {
        let id = output.trim();
        if !id.is_empty() && id.bytes().all(|byte| byte.is_ascii_digit()) {
            return Ok(PanelInputTarget::X11(id.to_owned()));
        }
    }
    // Do not repeat a failed Sway query in the same Wayland probe sequence.
    if !wayland_session {
        if let Some(target) = sway_target() {
            return Ok(target);
        }
    }
    Err(HostActionError { code: "unavailable" })
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
        0x13 => 119,
        0x10 => 42,
        0x11 => 29,
        0x12 => 56,
        0xa1 => 54,
        0xa3 => 97,
        0xa5 => 100,
        0x14 => 58,
        0x1b => 1,
        0x21 => 104,
        0x22 => 109,
        0x23 => 107,
        0x24 => 102,
        0x25 => 105,
        0x26 => 103,
        0x27 => 106,
        0x28 => 108,
        0x2c => 99,
        0x2d => 110,
        0x5b => 125,
        0x5c => 126,
        0x5d => 127,
        0x70..=0x79 => virtual_key - 0x70 + 59,
        0x7a => 87,
        0x7b => 88,
        0x60..=0x69 => [82, 79, 80, 81, 75, 76, 77, 71, 72, 73][(virtual_key - 0x60) as usize],
        0x6a => 55,
        0x6b => 78,
        0x6c => 121,
        0x6d => 74,
        0x6e => 83,
        0x6f => 98,
        0x90 => 69,
        0x91 => 70,
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
        0xe2 => 86,
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
        0x13 => "Pause",
        0x10 => "Shift_L",
        0x11 => "Control_L",
        0x12 => "Alt_L",
        0xa1 => "Shift_R",
        0xa3 => "Control_R",
        0xa5 => "Alt_R",
        0x14 => "Caps_Lock",
        0x1b => "Escape",
        0x21 => "Prior",
        0x22 => "Next",
        0x23 => "End",
        0x24 => "Home",
        0x25 => "Left",
        0x26 => "Up",
        0x27 => "Right",
        0x28 => "Down",
        0x2c => "Print",
        0x2d => "Insert",
        0x5b => "Super_L",
        0x5c => "Super_R",
        0x5d => "Menu",
        0x60..=0x69 => return Some(format!("KP_{}", virtual_key - 0x60)),
        0x6a => "KP_Multiply",
        0x6b => "KP_Add",
        0x6c => "KP_Separator",
        0x6d => "KP_Subtract",
        0x6e => "KP_Decimal",
        0x6f => "KP_Divide",
        0x90 => "Num_Lock",
        0x91 => "Scroll_Lock",
        0x70..=0x7b => return Some(format!("F{}", virtual_key - 0x70 + 1)),
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
        0xe2 => "less",
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
fn focus_wtype_target(target: &PanelInputTarget) -> Result<(), HostActionError> {
    if let PanelInputTarget::Sway(id) = target {
        let command = format!("[con_id={id}] focus");
        let reply = linux_process::read_text(
            "swaymsg",
            &["-r", &command],
            4096,
            std::time::Duration::from_secs(2),
        )
        .ok_or(HostActionError { code: "unavailable" })?;
        let results: Vec<serde_json::Value> = serde_json::from_str(&reply)
            .map_err(|_| HostActionError { code: "unavailable" })?;
        if results.is_empty() || results.iter().any(|result| {
            result.get("success").and_then(serde_json::Value::as_bool) != Some(true)
        }) {
            return Err(HostActionError { code: "unavailable" });
        }
        // A successful command is insufficient when the window disappeared or
        // focus changed. Confirm the actual destination before virtual input.
        let tree = linux_process::read_text(
            "swaymsg",
            &["-t", "get_tree", "-r"],
            1024 * 1024,
            std::time::Duration::from_secs(1),
        )
        .ok_or(HostActionError { code: "unavailable" })?;
        let tree: serde_json::Value = serde_json::from_str(&tree)
            .map_err(|_| HostActionError { code: "unavailable" })?;
        if focused_sway_container(&tree) != Some(*id) {
            return Err(HostActionError { code: "unavailable" });
        }
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn run_wtype(target: &PanelInputTarget, args: &[String]) -> Result<(), HostActionError> {
    if matches!(target, PanelInputTarget::Ydotool) {
        return run_ydotool(args);
    }
    focus_wtype_target(target)?;
    let arguments: Vec<&str> = args.iter().map(String::as_str).collect();
    linux_process::read_text(
        "wtype",
        &arguments,
        64,
        std::time::Duration::from_secs(3),
    )
    .map(|_| ())
    .ok_or(HostActionError { code: "unavailable" })
}

#[cfg(target_os = "linux")]
fn release_panel_focus(
    app: &tauri::AppHandle,
    target: &PanelInputTarget,
) -> Result<(), HostActionError> {
    if !matches!(target, PanelInputTarget::Wayland | PanelInputTarget::Ydotool) {
        return Ok(());
    }
    let windows: Vec<_> = [
        "handwriting-panel",
        "emoji-panel",
        "clipboard-panel",
        "voice-panel",
        "cloud-clipboard-panel",
        "cloud-dictionary-panel",
    ]
    .into_iter()
    .filter_map(|label| app.get_webview_window(label))
    .collect();
    let mut focused = false;
    for window in &windows {
        focused |= window.is_focused().map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    }
    if focused {
        // Hide every editable panel so the compositor cannot focus another one.
        // The screen keyboard never accepts focus and stays available for typing.
        for window in windows {
            window.hide().map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn send_x11_panel_key(window: &str, key: &str) -> Result<(), HostActionError> {
    // Explicit --window key delivery uses XSendEvent, which many applications
    // reject. Activate first, then use XTEST through the empty window stack.
    // Bound activation as a window manager may decline to focus the target.
    linux_process::read_text(
        "xdotool",
        &["windowactivate", "--sync", window, "key", key],
        64,
        std::time::Duration::from_secs(3),
    )
    .map(|_| ())
    .ok_or(HostActionError { code: "unavailable" })
}

#[cfg(target_os = "linux")]
fn send_panel_key(
    app: &tauri::AppHandle,
    target: PanelInputTarget,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_key",
    })?;
    if let PanelInputTarget::X11(window) = &target {
        let key = xdotool_key_args(&request).ok_or(HostActionError {
            code: "invalid_key",
        })?;
        return send_x11_panel_key(window, &key);
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
        release_panel_focus(app, &target)?;
        return run_ydotool(&command_args);
    }
    let key = xdotool_key_name(request.virtual_key).ok_or(HostActionError {
        code: "invalid_key",
    })?;
    release_panel_focus(app, &target)?;
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
fn send_panel_text_to_target(
    app: &tauri::AppHandle,
    target: &PanelInputTarget,
    text: &str,
) -> Result<(), HostActionError> {
    // ydotool types an ASCII key map, while newlines and tabs must remain
    // literal text rather than becoming application shortcuts on any backend.
    let literal_transfer = text.chars().any(|character| matches!(character, '\n' | '\r' | '\t'))
        || (matches!(target, PanelInputTarget::Ydotool) && !text.is_ascii());
    if literal_transfer {
        if !write_linux_clipboard(text) {
            return Err(HostActionError { code: "unavailable" });
        }
        std::thread::sleep(std::time::Duration::from_millis(30));
        return send_panel_ctrl_v(app, target);
    }
    release_panel_focus(app, target)?;
    if let PanelInputTarget::X11(window) = target {
        // Use focused XTEST input for applications that reject XSendEvent.
        // --file - reads stdin, keeping the text out of process arguments.
        return linux_process::write_input(
            "xdotool",
            &["windowactivate", "--sync", window.as_str(), "type", "--delay", "0", "--file", "-"],
            text.as_bytes(),
            std::time::Duration::from_secs(3),
        )
        .then_some(())
        .ok_or(HostActionError { code: "unavailable" });
    }
    let sent = if matches!(target, PanelInputTarget::Ydotool) {
        // ydotool may hold each ASCII key for 20ms even with key-delay=0.
        // Allow that per-character work while keeping stalls bounded.
        let timeout = std::time::Duration::from_millis(3000 + text.len() as u64 * 30);
        linux_process::write_input(
            "ydotool",
            &["type", "--escape", "0", "--key-delay", "0", "--file", "-"],
            text.as_bytes(),
            timeout,
        )
    } else {
        focus_wtype_target(target)?;
        linux_process::write_input(
            "wtype",
            &["-"],
            text.as_bytes(),
            std::time::Duration::from_secs(3),
        )
    };
    sent.then_some(()).ok_or(HostActionError { code: "unavailable" })
}

#[cfg(target_os = "linux")]
async fn send_panel_text(
    app: tauri::AppHandle,
    state: &tauri::State<'_, PanelInputState>,
    text: String,
) -> Result<(), HostActionError> {
    if text.is_empty()
        || text.len() > 4096
        || text.chars().any(|character| {
            character.is_control() && !matches!(character, '\n' | '\r' | '\t')
        })
    {
        return Err(HostActionError { code: "invalid_text" });
    }
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
    tauri::async_runtime::spawn_blocking(move || {
        send_panel_text_to_target(&app, &target, &text)
    })
    .await
    .map_err(|_| HostActionError { code: "unavailable" })?
}

#[cfg(target_os = "linux")]
fn send_panel_ctrl_v(
    app: &tauri::AppHandle,
    target: &PanelInputTarget,
) -> Result<(), HostActionError> {
    release_panel_focus(app, target)?;
    if let PanelInputTarget::X11(window) = target {
        return send_x11_panel_key(window, "ctrl+v");
    }
    if let PanelInputTarget::Ydotool = target {
        return run_ydotool(&[
            "key".to_owned(),
            "29:1".to_owned(),
            "47:1".to_owned(),
            "47:0".to_owned(),
            "29:0".to_owned(),
        ]);
    }
    run_wtype(
        target,
        &[
            "-M".to_owned(),
            "ctrl".to_owned(),
            "-k".to_owned(),
            "v".to_owned(),
        ],
    )
}

#[cfg(target_os = "linux")]
fn send_panel_voice_text(
    app: &tauri::AppHandle,
    target: &PanelInputTarget,
    text: &str,
    commit_mode: &str,
) -> Result<(), HostActionError> {
    if text.is_empty()
        || text.len() > 4096
        || text.chars().any(|character| {
            character.is_control() && !matches!(character, '\n' | '\r' | '\t')
        })
    {
        return Err(HostActionError {
            code: "invalid_text",
        });
    }
    let multiline = text.chars().any(|character| matches!(character, '\n' | '\r' | '\t'));
    if commit_mode == "ctrl_v" || multiline {
        if write_linux_clipboard(text) {
            std::thread::sleep(std::time::Duration::from_millis(30));
            return send_panel_ctrl_v(app, target);
        }
        // Do not turn literal newlines/tabs into Return/Tab key actions when
        // clipboard transfer fails; leave the transcript available to retry.
        if multiline {
            return Err(HostActionError { code: "unavailable" });
        }
    }
    send_panel_text_to_target(app, target, text)
}

// Windows panels are ordinary Tauri windows that never activate, so the host
// injects input on their behalf through the Windows host layer; this shell
// itself stays free of unsafe code.
#[cfg(target_os = "windows")]
fn remember_panel_input_target(
    state: &tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    let target = msime_host_windows::foreground_window().ok_or(HostActionError {
        code: "unavailable",
    })?;
    *state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })? = Some(PanelInputTarget(target));
    Ok(())
}

#[cfg(target_os = "windows")]
fn focused_panel_target(state: &tauri::State<'_, PanelInputState>) -> Result<(), HostActionError> {
    let target = state
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
    msime_host_windows::focus(target.0)
        .then_some(())
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "windows")]
fn send_panel_key_windows(
    state: &tauri::State<'_, PanelInputState>,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_key",
    })?;
    focused_panel_target(state)?;
    // Sticky modifiers only travel with keys the panel marked as inheriting
    // them; shift always applies to the key being sent.
    let sticky = request.include_sticky_modifiers;
    let modifiers = msime_host_windows::Modifiers {
        shift: request.shift,
        ctrl: sticky && request.modifiers.ctrl,
        alt: sticky && request.modifiers.alt,
        win: sticky && request.modifiers.win,
    };
    msime_host_windows::send_key(request.virtual_key, modifiers)
        .then_some(())
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "windows")]
fn send_panel_text_windows(
    state: &tauri::State<'_, PanelInputState>,
    text: &str,
) -> Result<(), HostActionError> {
    focused_panel_target(state)?;
    msime_host_windows::send_text(text)
        .then_some(())
        .ok_or(HostActionError {
            code: "invalid_text",
        })
}

// Panels sit bottom-centered on the work area, where the native ones did.
#[cfg(target_os = "windows")]
fn windows_panel_position(width: f64, height: f64) -> Option<(f64, f64)> {
    msime_host_windows::work_area().map(|area| area.bottom_center(width, height))
}

#[tauri::command]
fn remember_input_target(state: tauri::State<'_, PanelInputState>) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    return remember_panel_input_target(&state, false);
    #[cfg(target_os = "windows")]
    return remember_panel_input_target(&state);
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = state;
        Ok(())
    }
}

#[tauri::command]
async fn send_key(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    state: tauri::State<'_, PanelInputState>,
    request: KeyboardInputRequest,
) -> Result<(), HostActionError> {
    // Linux routes through the display server, Windows injects directly, so the
    // app handle belongs to only one of them.
    let _ = (&app, &window);
    #[cfg(target_os = "linux")]
    {
        request.validate().map_err(|_| HostActionError { code: "invalid_key" })?;
        // The non-focusable keyboard follows the editor the user is typing
        // into now, like Windows RememberInputTargetWindow on each key press.
        // Other panels retain their original destination while being edited.
        let target = if window.label() == "keyboard-panel" {
            None
        } else {
            Some(state
                .0
                .lock()
                .map_err(|_| HostActionError { code: "unavailable" })?
                .clone()
                .ok_or(HostActionError { code: "unavailable" })?)
        };
        return tauri::async_runtime::spawn_blocking(move || {
            let target = match target {
                Some(target) => target,
                None => capture_panel_input_target()?,
            };
            send_panel_key(&app, target, request)
        })
        .await
        .map_err(|_| HostActionError { code: "unavailable" })?;
    }
    #[cfg(target_os = "windows")]
    return send_panel_key_windows(&state, request);
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
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
    let options = options.inner().clone();
    let model = tauri::async_runtime::spawn_blocking(move || {
        let document = options.snapshot().map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        let document = serde_json::to_string(&document).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        Ok::<_, HostActionError>(packaged_handwriting_model(&document))
    })
    .await
    .map_err(|_| HostActionError {
        code: "unavailable",
    })??;
    // A user-managed socket owns recognizer and model policy where one is
    // configured; otherwise the Engine's packaged recognizer answers, which is
    // the only path hosts without unix sockets have.
    #[cfg(unix)]
    let socket = match std::env::var_os("MSIME_HANDWRITING_PROVIDER_SOCKET") {
        Some(value) => {
            let path = PathBuf::from(value);
            if !path.is_absolute() {
                return Err(HostActionError {
                    code: "unavailable",
                });
            }
            Some(path)
        }
        None => discover_session_provider("handwriting.sock"),
    };
    #[cfg(unix)]
    if let Some(path) = socket {
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
    let Some(model) = model else {
        return Err(HostActionError {
            code: "unavailable",
        });
    };
    let candidates = tauri::async_runtime::spawn_blocking(move || {
        msime_host_api::handwriting_local_candidates(model.to_str().unwrap_or_default(), &query)
    })
    .await
    .map_err(|_| HostActionError {
        code: "unavailable",
    })?
    .map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    let result = HandwritingRecognitionResult { candidates };
    result.validate().map_err(|_| HostActionError {
        code: "invalid_stroke",
    })?;
    Ok(result)
}

/// Locate the Engine's packaged handwriting model: the host options first, then
/// an explicit override, then the layouts the installers produce. Only an
/// absolute path to a file that exists is accepted, so a stale setting cannot
/// send strokes at something else.
fn packaged_handwriting_model(host_options: &str) -> Option<PathBuf> {
    serde_json::from_str::<Value>(host_options)
        .ok()
        .and_then(|value| {
            value
                .get("handwriting_model")
                .and_then(Value::as_str)
                .filter(|value| !value.is_empty())
                .map(str::to_owned)
        })
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("MSIME_HANDWRITING_MODEL")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from))
        .or_else(|| {
            discover_packaged_file(
                "msime-client/handwriting/handwriting-zh_CN.model",
                "handwriting/handwriting-zh_CN.model",
            )
        })
        .filter(|path| path.is_absolute() && path.is_file())
}

#[cfg(target_os = "linux")]
fn packaged_emoji_resources(document: &Value) -> Option<PathBuf> {
    // Explicit configuration owns catalog selection: invalid paths must not
    // silently switch to a different installed catalog.
    let configured = document
        .get("resources")
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .or_else(|| {
            std::env::var_os("MSIME_EMOJI_RESOURCES")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
        });
    if let Some(directory) = configured {
        return (directory.is_absolute() && directory.join("others.db").is_file())
            .then_some(directory);
    }
    discover_packaged_file("msime-client/emoji/others.db", "emoji/others.db")
        .and_then(|path| path.parent().map(std::path::Path::to_path_buf))
}

fn discover_packaged_file(relative: &str, beside_executable: &str) -> Option<PathBuf> {
    let mut candidates = Vec::new();

    #[cfg(target_os = "linux")]
    {
        let data_home = std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .or_else(|| {
                std::env::var_os("HOME")
                    .map(PathBuf::from)
                    .filter(|path| path.is_absolute())
                    .map(|path| path.join(".local/share"))
            });
        if let Some(root) = data_home {
            candidates.push(root.join(relative));
        }
    }

    if let Ok(executable) = std::env::current_exe() {
        if let Some(directory) = executable.parent() {
            // Preserve the Windows bundle and relocatable Unix prefix layouts.
            candidates.push(directory.join(beside_executable));
            if let Some(prefix) = directory.parent() {
                candidates.push(prefix.join("share").join(relative));
            }
        }
    }

    #[cfg(target_os = "linux")]
    {
        let directories = std::env::var_os("XDG_DATA_DIRS")
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "/usr/local/share:/usr/share".into());
        candidates.extend(
            std::env::split_paths(&directories)
                .filter(|path| path.is_absolute())
                .map(|path| path.join(relative)),
        );
    }

    candidates
        .into_iter()
        .find(|path| path.is_absolute() && path.is_file())
}

#[derive(serde::Deserialize)]
struct VoiceRecognitionRequest {
    language: String,
    request_id: String,
}

#[derive(serde::Serialize)]
struct VoiceRecognitionResult {
    text: String,
}

#[cfg(unix)]
#[derive(serde::Serialize, Clone)]
struct VoiceRecognitionUpdate {
    text: String,
    request_id: String,
    #[serde(rename = "final")]
    final_result: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    phase: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    level: Option<f32>,
}

#[cfg(unix)]
fn voice_provider_options(document: &Value) -> Result<Value, HostActionError> {
    let Some(voice) = document
        .get("preferences")
        .and_then(|value| value.get("voice_input"))
        .and_then(Value::as_object)
    else {
        return Ok(Value::Object(Default::default()));
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
        "stream_inline_preedit",
    ] {
        if let Some(value) = voice.get(key).filter(|value| value.is_boolean()) {
            options.insert(key.to_owned(), value.clone());
        }
    }
    for key in [
        "capture_backend",
        "capture_device",
        "commit_mode",
        "asr_provider",
        "asr_model",
        "asr_resource_id",
        "polish_provider",
        "polish_model",
        "polish_prompt_id",
        "doubao_boosting_table_id",
    ] {
        if let Some(value) = voice.get(key).and_then(Value::as_str) {
            let bounded = value.chars().take(512).collect::<String>();
            options.insert(key.to_owned(), Value::String(bounded));
        }
    }
    let preset = voice.get("polish_prompt_id").and_then(Value::as_str).unwrap_or("cleanup");
    let prompt_key = match preset {
        "custom" | "custom_1" => Some("polish_prompt_custom_1"),
        "custom_2" => Some("polish_prompt_custom_2"),
        "custom_3" => Some("polish_prompt_custom_3"),
        _ => None,
    };
    if let Some(key) = prompt_key {
        let mut prompt = voice.get(key).and_then(Value::as_str).unwrap_or("");
        if prompt.is_empty() && key == "polish_prompt_custom_1" {
            prompt = voice.get("polish_prompt").and_then(Value::as_str).unwrap_or("");
        }
        if prompt.len() > 8192 {
            return Err(HostActionError { code: "invalid_voice" });
        }
        if !prompt.is_empty() {
            options.insert(key.to_owned(), Value::String(prompt.to_owned()));
        }
    }
    Ok(Value::Object(options))
}

// Resolve on each request so services started after the panel remain discoverable.
#[cfg(unix)]
fn discover_session_provider(filename: &str) -> Option<PathBuf> {
    std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .filter(|directory| directory.is_absolute())
        .map(|directory| directory.join("msime-client").join(filename))
        .filter(|path| {
            path.metadata()
                .map(|metadata| metadata.file_type().is_socket())
                .unwrap_or(false)
        })
}

#[cfg(unix)]
fn resolve_voice_provider_socket(document: &serde_json::Value) -> Option<std::path::PathBuf> {
    document
        .get("voice_provider_socket")
        .and_then(serde_json::Value::as_str)
        .map(std::path::PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            std::env::var_os("MSIME_VOICE_PROVIDER_SOCKET")
                .map(std::path::PathBuf::from)
                .filter(|path| path.is_absolute())
        })
        .or_else(|| discover_session_provider("voice.sock"))
}

#[tauri::command]
async fn recognize_voice(
    app: tauri::AppHandle,
    request: VoiceRecognitionRequest,
    runtime: tauri::State<'_, RuntimeOptionsState>,
    store: tauri::State<'_, Arc<PreferencesStore>>,
) -> Result<VoiceRecognitionResult, HostActionError> {
    // Streaming updates are emitted by the unix provider path only.
    #[cfg(not(unix))]
    let _ = (&app, &runtime, &store);
    if request.request_id.is_empty()
        || request.request_id.len() > 64
        || !request
            .request_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-')
        || request.language.is_empty()
        || request.language.len() > 64
        || request.language.chars().any(char::is_control)
    {
        return Err(HostActionError {
            code: "invalid_voice",
        });
    }
    #[cfg(unix)]
    {
        let runtime = runtime.inner().clone();
        let store = store.inner().clone();
        let document = tauri::async_runtime::spawn_blocking(move || {
            let document = runtime.snapshot().map_err(|_| HostActionError {
                code: "unavailable",
            })?;
            // The shared preference store is also written by IBus and other
            // settings windows; new recordings must use those saved settings.
            #[cfg(target_os = "linux")]
            let document = {
                let mut document = document;
                let preferences = store.load().map_err(|_| HostActionError {
                    code: "unavailable",
                })?;
                document["preferences"] = serde_json::to_value(preferences.preferences)
                    .map_err(|_| HostActionError {
                        code: "unavailable",
                    })?;
                document
            };
            #[cfg(not(target_os = "linux"))]
            let _ = store;
            Ok::<_, HostActionError>(document)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })??;
        let provider_options = voice_provider_options(&document)?;
        let path = resolve_voice_provider_socket(&document).ok_or(HostActionError {
            code: "unavailable",
        })?;
        let sessions = app.state::<voice_sessions::VoiceSessions>();
        let session = sessions
            .begin(request.request_id, path)
            .ok_or(HostActionError { code: "busy" })?;
        let generation = session.generation;
        let language = request.language;
        let worker_app = app.clone();
        let result = tauri::async_runtime::spawn_blocking(move || {
            let mut update = |text: &str, final_result: bool| {
                if session.cancelled.load(std::sync::atomic::Ordering::Relaxed) {
                    return;
                }
                let _ = worker_app.emit(
                    "voice-update",
                    VoiceRecognitionUpdate {
                        text: text.to_owned(),
                        request_id: session.request_id.clone(),
                        final_result,
                        phase: None,
                        level: None,
                    },
                );
            };
            let mut status = |phase: &str| {
                if session.cancelled.load(std::sync::atomic::Ordering::Relaxed) {
                    return;
                }
                let _ = worker_app.emit("voice-update", VoiceRecognitionUpdate {
                    text: String::new(),
                    request_id: session.request_id.clone(),
                    final_result: false,
                    phase: Some(phase.to_owned()),
                    level: None,
                });
            };
            let mut level = |level: f32| {
                if session.cancelled.load(std::sync::atomic::Ordering::Relaxed) { return; }
                let _ = worker_app.emit("voice-update", VoiceRecognitionUpdate {
                    text: String::new(),
                    request_id: session.request_id.clone(),
                    final_result: false,
                    phase: None,
                    level: Some(level),
                });
            };
            UnixSocketProvider::new(session.path.clone()).voice_stream_with_options_feedback(
                &language,
                generation,
                &provider_options,
                Some(&session.cancelled),
                &mut update,
                Some(&mut status),
                Some(&mut level),
            )
        })
        .await;
        sessions.finish(generation);
        let text = result
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        Ok(VoiceRecognitionResult { text })
    }
    #[cfg(not(unix))]
    {
        let _ = (request, runtime);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn stop_voice(app: tauri::AppHandle, request_id: String) -> Result<(), HostActionError> {
    #[cfg(unix)]
    {
        let sessions = app.state::<voice_sessions::VoiceSessions>();
        let Some(session) = sessions.active(&request_id) else {
            return Ok(());
        };
        if UnixSocketProvider::new(session.path).voice_stop(session.generation) {
            return Ok(());
        }
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(not(unix))]
    {
        let _ = (app, request_id);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn cancel_voice(app: tauri::AppHandle, request_id: Option<String>) -> Result<(), HostActionError> {
    #[cfg(unix)]
    {
        let sessions = app.state::<voice_sessions::VoiceSessions>();
        let Some(session) = sessions.cancel(request_id.as_deref()) else {
            return Ok(());
        };
        if UnixSocketProvider::new(session.path).voice_cancel(session.generation) {
            return Ok(());
        }
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(not(unix))]
    {
        let _ = (app, request_id);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn submit_handwriting_candidate(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    candidate: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        msime_client_core::panels::validate_candidate(&candidate)
            .map_err(|_| HostActionError { code: "invalid_text" })?;
        return send_panel_text(app, &state, candidate).await;
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, candidate);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn send_text(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    text: String,
) -> Result<(), HostActionError> {
    let _ = &app;
    #[cfg(target_os = "linux")]
    return send_panel_text(app, &state, text).await;
    #[cfg(target_os = "windows")]
    return send_panel_text_windows(&state, &text);
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = (app, state, text);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn supports_clipboard_paste() -> bool {
    cfg!(target_os = "linux")
}

#[tauri::command]
async fn paste_clipboard_text(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    text: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        if text.is_empty() || text.len() > msime_client_core::clipboard::MAX_TEXT_BYTES || text.contains('\0') {
            return Err(HostActionError { code: "invalid_text" });
        }
        let target = state
            .0
            .lock()
            .map_err(|_| HostActionError { code: "unavailable" })?
            .clone()
            .ok_or(HostActionError { code: "unavailable" })?;
        tauri::async_runtime::spawn_blocking(move || {
            if !write_linux_clipboard(&text) {
                return Err(HostActionError { code: "unavailable" });
            }
            send_panel_ctrl_v(&app, &target)
        })
        .await
        .map_err(|_| HostActionError { code: "unavailable" })?
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, text);
        Err(HostActionError { code: "unavailable" })
    }
}

#[tauri::command]
async fn send_voice_text(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    text: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        let target = state
            .0
            .lock()
            .map_err(|_| HostActionError { code: "unavailable" })?
            .clone()
            .ok_or(HostActionError { code: "unavailable" })?;
        let store = store.inner().clone();
        return tauri::async_runtime::spawn_blocking(move || {
            let commit_mode = store
                .load()
                .map_err(|_| HostActionError { code: "unavailable" })?
                .preferences
                .voice_input
                .commit_mode;
            send_panel_voice_text(&app, &target, &text, &commit_mode)
        })
        .await
        .map_err(|_| HostActionError { code: "unavailable" })?;
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = (app, state, store, text);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn voice_input_language(
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<String, HostActionError> {
    store
        .inner()
        .load()
        .map(|snapshot| {
            let language = snapshot.preferences.voice_input.language;
            if language.is_empty() {
                "zh-CN".to_owned()
            } else {
                language
            }
        })
        .map_err(|_| HostActionError {
            code: "unavailable",
        })
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

fn panel_accepts_focus(label: &str) -> bool {
    label != "keyboard-panel"
}

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
        let accepts_focus = panel_accepts_focus(label);
        if let Some(window) = app.get_webview_window(label) {
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if let Some((x, y)) = position {
                let _ = window.set_position(tauri::Position::Physical(
                    tauri::PhysicalPosition::new(x.round() as i32, y.round() as i32),
                ));
            }
            window
                .show()
                .and_then(|_| {
                    if accepts_focus {
                        window.set_focus()
                    } else {
                        Ok(())
                    }
                })
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
            .focused(accepts_focus)
            .focusable(accepts_focus)
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
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 1100.0, 400.0)
        };
        // The panel never activates, so the window that owns the caret now is
        // the one synthetic input has to reach later.
        #[cfg(target_os = "windows")]
        let position = {
            let _ = remember_panel_input_target(&state);
            windows_panel_position(1100.0, 400.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
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
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = &state;
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, 980.0, 650.0)
        };
        // The panel never activates, so the window that owns the caret now is
        // the one synthetic input has to reach later.
        #[cfg(target_os = "windows")]
        let position = {
            let _ = remember_panel_input_target(&state);
            windows_panel_position(980.0, 650.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
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
    {
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
        let _ = (&options, &input);
        #[cfg(target_os = "linux")]
        let position = {
            let _ = &options;
            let _ = remember_panel_input_target(&input, true);
            panel_position(&input, 720.0, 720.0)
        };
        #[cfg(target_os = "windows")]
        let position = {
            let _ = &options;
            let _ = remember_panel_input_target(&input);
            windows_panel_position(720.0, 720.0)
        };
        #[cfg(not(any(target_os = "linux", target_os = "windows")))]
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
        Err(HostActionError {
            code: "unavailable",
        })
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
        Err(HostActionError {
            code: "unavailable",
        })
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
        Err(HostActionError {
            code: "unavailable",
        })
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
    if label == "voice-panel" {
        let _ = cancel_voice(app.clone(), None);
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
    let mut commands: Vec<(&str, &[&str])> = Vec::new();
    if std::env::var_os("WAYLAND_DISPLAY").is_some_and(|value| !value.is_empty()) {
        commands.push(("wl-paste", &["--no-newline", "--type", "text"]));
    }
    if std::env::var_os("DISPLAY").is_some_and(|value| !value.is_empty()) {
        commands.push(("xclip", &["-selection", "clipboard", "-o"]));
        commands.push(("xsel", &["--clipboard", "--output"]));
    }
    // Preserve source line endings; wl-paste suppresses its own separator.
    commands
        .into_iter()
        .find_map(|(program, arguments)| linux_clipboard::read_text(program, arguments))
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn write_linux_clipboard(text: &str) -> bool {
    if std::env::var_os("WAYLAND_DISPLAY").is_some_and(|value| !value.is_empty())
        && linux_clipboard::write_text("wl-copy", &["--type", "text/plain;charset=utf-8"], text)
    {
        return true;
    }
    if std::env::var_os("DISPLAY").is_some_and(|value| !value.is_empty()) {
        return linux_clipboard::write_text("xclip", &["-selection", "clipboard"], text)
            || linux_clipboard::write_text("xsel", &["--clipboard", "--input"], text);
    }
    false
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
                        match preferences.capture_clipboard_text(text.clone()) {
                            Ok(true) => {
                                if let Ok(mut store) = history.lock() {
                                    let _ = store.load();
                                }
                                last_text = Some(text);
                            }
                            Ok(false) => last_text = None,
                            Err(_) => {}
                        }
                    }
                }
                std::thread::sleep(std::time::Duration::from_millis(750));
            }
        });
}

#[tauri::command]
async fn list_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<Vec<String>, HostActionError> {
    let state = state.inner().clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || list_clipboard_history_blocking(&state, &store))
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
}

fn list_clipboard_history_blocking(
    state: &ClipboardHistoryState,
    store: &Arc<PreferencesStore>,
) -> Result<Vec<String>, HostActionError> {
    if !clipboard_enabled(store)? {
        return Ok(Vec::new());
    }
    let mut history = state
        .0
        .lock()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    history.load().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    Ok(history.entries().to_vec())
}

#[tauri::command]
async fn remove_clipboard_history(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<(), HostActionError> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .remove(&text)
            .map(|_| ())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    })
    .await
    .map_err(|_| HostActionError {
        code: "unavailable",
    })?
}

#[tauri::command]
async fn clear_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<(), HostActionError> {
    let state = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || clear_clipboard_history_blocking(&state))
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
}

fn clear_clipboard_history_blocking(
    state: &ClipboardHistoryState,
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
async fn sync_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<Vec<String>, HostActionError> {
    let state = state.inner().clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || sync_clipboard_history_blocking(&state, &store))
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
}

fn sync_clipboard_history_blocking(
    state: &ClipboardHistoryState,
    store: &Arc<PreferencesStore>,
) -> Result<Vec<String>, HostActionError> {
    if !clipboard_enabled(store)? {
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
    store.capture_clipboard_text(text).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    let mut history = state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    history.load().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    Ok(history.entries().to_vec())
}

#[tauri::command]
async fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<(), HostActionError> {
    let state = state.inner().clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || copy_text_blocking(text, &state, &store))
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
}

fn copy_text_blocking(
    text: String,
    state: &ClipboardHistoryState,
    store: &Arc<PreferencesStore>,
) -> Result<(), HostActionError> {
    let enabled = clipboard_enabled(store)?;
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
        store.capture_clipboard_text(text).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .load()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
    }
    Ok(())
}

#[cfg(target_os = "linux")]
fn linux_runtime_state_directory() -> Result<Option<PathBuf>, String> {
    let Some(options_path) = std::env::var_os("MSIME_CLIENT_HOST_OPTIONS")
        .or_else(|| std::env::var_os("MSIME_IBUS_OPTIONS"))
    else {
        return Ok(None);
    };
    let options_path = PathBuf::from(options_path);
    if !options_path.is_absolute() {
        return Err("Runtime options path must be absolute".into());
    }
    let options = fs::read_to_string(options_path)
        .map_err(|_| "Cannot read runtime options for shared state".to_owned())?;
    let options: Value = serde_json::from_str(&options)
        .map_err(|_| "Cannot parse runtime options for shared state".to_owned())?;
    match options.get("preferences_directory") {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if value.is_empty() => Ok(None),
        Some(Value::String(value)) if PathBuf::from(value).is_absolute() => {
            Ok(Some(PathBuf::from(value)))
        }
        _ => Err("Runtime preferences directory must be absolute".into()),
    }
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
                None => {
                    #[cfg(target_os = "linux")]
                    let runtime_directory = linux_runtime_state_directory()?;
                    #[cfg(not(target_os = "linux"))]
                    let runtime_directory: Option<PathBuf> = None;
                    match runtime_directory {
                        Some(path) => path,
                        None => app.path().app_data_dir()?,
                    }
                }
            };
            let mut clipboard =
                ClipboardHistoryStore::open(directory.join("clipboard_history.json"));
            let _ = clipboard.load();
            let preferences = Arc::new(PreferencesStore::new(&directory));
            app.manage(CustomSkinLibraryStore::new(&directory));
            app.manage(TypingStatisticsState(TypingStatisticsStore::new(&directory)));
            app.manage(SkinDirectoryState(directory.join("skins")));
            app.manage(preferences.clone());
            let clipboard_state = ClipboardHistoryState(Arc::new(Mutex::new(clipboard)));
            app.manage(ClipboardHistoryState(Arc::clone(&clipboard_state.0)));
            #[cfg(target_os = "linux")]
            start_linux_preferences_monitor(
                app.handle(),
                preferences.clone(),
                Arc::clone(&clipboard_state.0),
            );
            #[cfg(target_os = "linux")]
            start_linux_clipboard_monitor(Arc::clone(&clipboard_state.0), preferences);
            app.manage(PanelInputState::default());
            #[cfg(unix)]
            app.manage(voice_sessions::VoiceSessions::default());
            // Native packaging/installer supplies this verified HostOptions JSON.
            // Webview input never controls resource or state paths.
            #[cfg(target_os = "android")]
            let host_options_path = app
                .path()
                .app_data_dir()?
                .join("files/runtime-options.json");
            #[cfg(not(target_os = "android"))]
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
            app.manage(DictionaryHostOptions {
                #[cfg(target_os = "linux")]
                path: host_options_path,
                #[cfg(not(target_os = "linux"))]
                document: Arc::new(host_document.clone()),
            });
            app.manage(RuntimeOptionsState {
                path: runtime_path,
                document: Arc::new(Mutex::new(host_document)),
            });
            // Both desktop hosts launch this shell with the panel their menu
            // named; the IBus property menu and the Windows tray menu are the
            // same contract, so the routes stay in one place.
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if let Ok(panel) = std::env::var("MSIME_CLIENT_PANEL") {
                let route = match panel.as_str() {
                    "keyboard" => Some((
                        "keyboard-panel",
                        "keyboard",
                        "水杉屏幕键盘",
                        1100.0,
                        400.0,
                    )),
                    "clipboard" => Some((
                        "clipboard-panel",
                        "clipboard",
                        "水杉本地剪贴板",
                        560.0,
                        620.0,
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
                    // The menu process is the panel launcher in this path, so
                    // capture the foreground editor before the new window can
                    // take focus. This is the same handoff used by the
                    // settings-page panel commands.
                    let panel_input = app.state::<PanelInputState>();
                    #[cfg(target_os = "linux")]
                    let position = {
                        let _ = remember_panel_input_target(&panel_input, true);
                        None
                    };
                    #[cfg(target_os = "windows")]
                    let position = {
                        let _ = remember_panel_input_target(&panel_input);
                        windows_panel_position(width, height)
                    };
                    if let Some(window) = app.get_webview_window("main") {
                        let _ = window.hide();
                    }
                    open_panel_window(
                        app.handle(), label, route, title, width, height, position,
                    )
                    .map_err(|_| "Cannot open requested panel".to_string())?;
                }
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            list_voice_capture_devices,
            supports_font_catalog,
            initial_settings_page,
            list_font_families,
            load_preferences,
            load_custom_skin_library,
            mutate_custom_skin_library,
            load_typing_statistics,
            set_typing_statistics_enabled,
            reset_typing_statistics,
            scan_skin_catalog,
            read_skin_image,
            read_skin_font,
            read_skin_toolbar_stylesheet,
            open_skin_directory,
            save_preferences,
            list_clipboard_history,
            clear_clipboard_history,
            remove_clipboard_history,
            sync_clipboard_history,
            copy_text,
            remember_input_target,
            send_key,
            send_text,
            send_voice_text,
            paste_clipboard_text,
            supports_clipboard_paste,
            voice_input_language,
            recognize_handwriting,
            recognize_voice,
            cancel_voice,
            stop_voice,
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
            load_emoji_catalog,
            restart_input_method
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

#[cfg(test)]
mod tests {
    #[test]
    fn requested_settings_page_only_accepts_a_plain_section_identifier() {
        assert_eq!(
            super::requested_settings_page(Some(" about ")),
            Some("about".into())
        );
        assert_eq!(
            super::requested_settings_page(Some("screen-keyboard")),
            Some("screen-keyboard".into())
        );
        assert_eq!(super::requested_settings_page(None), None);
        assert_eq!(super::requested_settings_page(Some("   ")), None);
        // Anything that could carry a path, a query or a script stays out of
        // the window the launcher is about to open.
        assert_eq!(super::requested_settings_page(Some("../etc")), None);
        assert_eq!(super::requested_settings_page(Some("About")), None);
        assert_eq!(super::requested_settings_page(Some("a?b=c")), None);
        assert_eq!(super::requested_settings_page(Some(&"a".repeat(33))), None);
    }

    #[test]
    fn packaged_handwriting_model_only_accepts_an_existing_absolute_file() {
        let directory = tempfile::tempdir().unwrap();
        let model = directory.path().join("handwriting-zh_CN.model");
        std::fs::write(&model, b"synthetic").unwrap();
        let options = |value: String| serde_json::json!({ "handwriting_model": value }).to_string();

        // The host options win when they name a model that is actually there.
        assert_eq!(
            super::packaged_handwriting_model(&options(model.to_string_lossy().into_owned())),
            Some(model.clone())
        );

        // A relative or missing path is refused rather than handed to the
        // recognizer, so a stale setting cannot send strokes at something else.
        assert_eq!(
            super::packaged_handwriting_model(&options("model".into())),
            None
        );
        assert_eq!(
            super::packaged_handwriting_model(&options(
                directory
                    .path()
                    .join("absent.model")
                    .to_string_lossy()
                    .into_owned()
            )),
            None
        );
    }

    #[test]
    fn typing_statistics_status_reports_file_availability_without_content() {
        let directory = tempfile::tempdir().unwrap();
        let store =
            msime_client_core::typing_statistics::TypingStatisticsStore::new(directory.path());
        let missing = super::typing_statistics_status(&store, store.load().unwrap())
            .ok()
            .unwrap();
        let missing_json = serde_json::to_value(missing).unwrap();
        assert_eq!(missing_json["availability"], "neverWritten");
        assert!(missing_json["lastWrittenMs"].is_null());
        assert_eq!(missing_json["statistics"]["enabled"], true);

        let disabled = store.set_enabled(false).unwrap();
        let ready = super::typing_statistics_status(&store, disabled)
            .ok()
            .unwrap();
        let ready_json = serde_json::to_value(ready).unwrap();
        assert_eq!(ready_json["availability"], "ready");
        assert!(ready_json["lastWrittenMs"].is_number());
        assert_eq!(ready_json["statistics"]["enabled"], false);
    }

    #[cfg(not(target_os = "windows"))]
    #[test]
    fn keyboard_does_not_accept_focus_but_editable_panels_do() {
        assert!(!super::panel_accepts_focus("keyboard-panel"));
        for label in [
            "handwriting-panel",
            "voice-panel",
            "emoji-panel",
            "cloud-clipboard-panel",
            "cloud-dictionary-panel",
        ] {
            assert!(super::panel_accepts_focus(label));
        }
    }
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
        std::fs::write(folder.join("font.woff2"), [0, 1, 255]).unwrap();
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
        let font = super::read_skin_font_at(root.clone(), "sample", "font.woff2")
            .ok()
            .unwrap();
        let font_json = serde_json::to_value(font).unwrap();
        assert_eq!(font_json["contentType"], "font/woff2");
        assert_eq!(font_json["bytes"], serde_json::json!([0, 1, 255]));
        assert!(super::read_skin_font_at(root.clone(), "sample", "preview.png").is_err());
        assert!(super::read_skin_font_at(root.clone(), "sample", "../font.woff2").is_err());
        assert!(super::read_skin_font_at(root.clone(), "../sample", "font.woff2").is_err());
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

#[cfg(target_os = "android")]
mod android_account;
#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos", test))]
mod desktop_preferences_monitor;
#[cfg(any(target_os = "ios", test))]
mod ios_account;
#[cfg(target_os = "linux")]
mod linux_audio_devices;
#[cfg(target_os = "linux")]
mod linux_clipboard;
#[cfg(target_os = "linux")]
mod linux_process;
#[cfg(target_os = "macos")]
mod macos_cloud_clipboard;
#[cfg(target_os = "macos")]
mod macos_cloud_dictionary;
#[cfg(any(target_os = "macos", test))]
mod macos_handwriting;
#[cfg(any(target_os = "macos", test))]
mod macos_keyboard;
#[cfg(any(target_os = "macos", test))]
mod macos_launch;
#[cfg(target_os = "macos")]
mod macos_panel_session;

use msime_client_core::clipboard::{ClipboardHistoryEntry, ClipboardHistoryStore};
use msime_client_core::custom_skin_library::{
    CustomSkinLibraryAction, CustomSkinLibraryError, CustomSkinLibraryStore, SavedTouchKeyboardSkin,
};
use msime_client_core::host_surface::{HostCapabilities, HostPlatform, SurfaceRoute};
use msime_client_core::keyboard_skin_trial::KeyboardSkinTrialStore;
use msime_client_core::panels::{
    HandwritingRecognitionRequest, HandwritingRecognitionResult, KeyboardInputRequest,
};
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
#[cfg(any(target_os = "linux", target_os = "windows"))]
use msime_client_core::typing_statistics::TypingSource;
use msime_client_core::typing_statistics::{TypingStatistics, TypingStatisticsStore};
#[cfg(target_os = "android")]
use msime_tauri_mobile_platform::AndroidVoicePlatform;
#[cfg(any(target_os = "ios", test))]
use msime_tauri_mobile_platform::IosVoiceRequestHeader;
#[cfg(target_os = "ios")]
use msime_tauri_mobile_platform::MobilePlatform;
#[cfg(any(target_os = "ios", test))]
use msime_tauri_mobile_platform::{IosKeyboardAiPreferences, IosVoiceTranscriptionRequest};
// The packaged recognizer runs on every host; only the socket provider is unix.
#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
use msime_input_runtime::UnixSocketProvider;
use msime_input_runtime::{HandwritingPoint, HandwritingQuery};
use serde_json::Value;
use std::collections::HashMap;
#[cfg(not(target_os = "macos"))]
use std::fs;
#[cfg(any(target_os = "linux", target_os = "windows"))]
use std::io::Write;
#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
use std::os::unix::fs::FileTypeExt;
#[cfg(any(target_os = "linux", target_os = "android", target_os = "ios"))]
use std::path::Path;
use std::path::PathBuf;
#[cfg(any(target_os = "linux", target_os = "windows"))]
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use tauri::Emitter;
use tauri::Manager;
#[cfg(not(mobile))]
use tauri::{WebviewUrl, WebviewWindowBuilder};

mod mobile_ai;
mod skin_directory;
#[cfg(any(target_os = "linux", target_os = "windows", test))]
mod voice_output;
#[cfg(any(
    all(unix, not(any(target_os = "ios", target_os = "android"))),
    target_os = "windows"
))]
mod voice_sessions;
#[cfg(windows)]
mod windows_voice;
use msime_host_api::system_fonts;

#[tauri::command]
fn supports_font_catalog() -> bool {
    system_fonts::supported()
}

/// The platform this shell is running on. The shared UI previously inferred this
/// from `navigator.userAgent`, which hid working controls on every host the
/// regex did not name.
fn host_platform() -> HostPlatform {
    if cfg!(target_os = "windows") {
        HostPlatform::Windows
    } else if cfg!(target_os = "macos") {
        HostPlatform::Macos
    } else if cfg!(target_os = "android") {
        HostPlatform::Android
    } else if cfg!(target_os = "ios") {
        HostPlatform::Ios
    } else {
        HostPlatform::Linux
    }
}

fn clipboard_history_uses_preference(platform: HostPlatform) -> bool {
    !matches!(platform, HostPlatform::Ios)
}

/// The surface a native host asked this shell to present, from `--route=<route>`,
/// `MSIME_CLIENT_ROUTE`, or the superseded `MSIME_CLIENT_PANEL`. An unparseable
/// route opens the ordinary settings window rather than failing startup.
fn requested_surface_route() -> Option<SurfaceRoute> {
    let argument = std::env::args()
        .skip(1)
        .find_map(|argument| argument.strip_prefix("--route=").map(str::to_string));
    let requested = argument
        .or_else(|| std::env::var("MSIME_CLIENT_ROUTE").ok())
        // Superseded by --route=; kept so existing menu launchers keep working.
        .or_else(|| std::env::var("MSIME_CLIENT_PANEL").ok())?;
    SurfaceRoute::parse(requested.trim()).ok()
}

#[tauri::command]
fn host_capabilities() -> HostCapabilities {
    let mut capabilities = HostCapabilities::for_platform(host_platform());
    // Font enumeration is a build-time capability, not a platform assumption.
    capabilities.system_fonts = system_fonts::supported();
    capabilities
}

/// The settings section a host menu asked for, if any. The launcher passes it
/// in the environment, like the panel routes; the settings page falls back to
/// its own default when this is absent or unusable.
#[tauri::command]
fn initial_settings_page() -> Option<String> {
    // A `settings:<category>` route is the contract every host now shares; the
    // dedicated variable stays as the compatibility path for older launchers.
    settings_page_from_route(requested_surface_route()).or_else(|| {
        requested_settings_page(std::env::var("MSIME_CLIENT_SETTINGS_PAGE").ok().as_deref())
    })
}

/// The settings category a surface route names, if it names one.
fn settings_page_from_route(route: Option<SurfaceRoute>) -> Option<String> {
    route
        .and_then(SurfaceRoute::settings_category)
        .map(|category| category.as_str().to_owned())
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
async fn resolve_font_families(names: Vec<String>) -> Result<Vec<String>, CommandError> {
    tauri::async_runtime::spawn_blocking(move || system_fonts::resolve_css_families(names))
        .await
        .map_err(|_| CommandError {
            code: "font_family",
        })?
        .map_err(|code| CommandError { code })
}

#[cfg(any(target_os = "macos", test))]
fn macos_voice_capture_devices(document: &Value) -> Vec<Value> {
    fn collect(value: &Value, devices: &mut Vec<Value>) {
        if devices.len() >= 128 {
            return;
        }
        if let Some(object) = value.as_object() {
            let input_channels = object
                .get("coreaudio_device_input")
                .and_then(Value::as_u64)
                .unwrap_or_default();
            if input_channels > 0 {
                if let Some(name) = object
                    .get("_name")
                    .and_then(Value::as_str)
                    .map(str::trim)
                    .filter(|name| {
                        !name.is_empty() && name.len() <= 512 && !name.chars().any(char::is_control)
                    })
                {
                    let id = object
                        .get("coreaudio_device_uid")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|id| {
                            !id.is_empty() && id.len() <= 512 && !id.chars().any(char::is_control)
                        })
                        .unwrap_or(name);
                    devices.push(serde_json::json!({
                        "backend": "macos",
                        "id": id,
                        "label": name
                    }));
                }
            }
            for child in object.values() {
                collect(child, devices);
            }
        } else if let Some(array) = value.as_array() {
            for child in array {
                collect(child, devices);
            }
        }
    }

    let mut devices = Vec::new();
    collect(document, &mut devices);
    devices
}

#[tauri::command]
async fn list_voice_capture_devices() -> Result<Value, CommandError> {
    #[cfg(target_os = "linux")]
    {
        let devices = tauri::async_runtime::spawn_blocking(linux_audio_devices::list)
            .await
            .map_err(|_| CommandError {
                code: "audio_devices",
            })?;
        serde_json::to_value(devices).map_err(|_| CommandError {
            code: "audio_devices",
        })
    }
    #[cfg(target_os = "windows")]
    {
        let devices = tauri::async_runtime::spawn_blocking(msime_host_api::voice_capture_devices)
            .await
            .map_err(|_| CommandError {
                code: "audio_devices",
            })?;
        serde_json::to_value(
            devices
                .into_iter()
                .map(|(id, label)| {
                    serde_json::json!({
                        "backend": "windows",
                        "id": id,
                        "label": label
                    })
                })
                .collect::<Vec<_>>(),
        )
        .map_err(|_| CommandError {
            code: "audio_devices",
        })
    }
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("system_profiler")
            .args(["SPAudioDataType", "-json"])
            .output()
            .map_err(|_| CommandError {
                code: "audio_devices",
            })?;
        if !output.status.success() {
            return Err(CommandError {
                code: "audio_devices",
            });
        }
        let document: Value = serde_json::from_slice(&output.stdout).map_err(|_| CommandError {
            code: "audio_devices",
        })?;
        Ok(Value::Array(macos_voice_capture_devices(&document)))
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    Err(CommandError {
        code: "unavailable",
    })
}

#[tauri::command]
async fn capture_voice_pcm(milliseconds: u32) -> Result<Vec<f32>, CommandError> {
    tauri::async_runtime::spawn_blocking(move || {
        msime_host_api::voice_capture_pcm(milliseconds).map_err(|code| CommandError { code })
    })
    .await
    .map_err(|_| CommandError {
        code: "audio_capture",
    })?
}

#[derive(Clone)]
struct ClipboardHistoryState(Arc<Mutex<ClipboardHistoryStore>>);
#[derive(Clone)]
struct DictionaryHostOptions {
    #[cfg(any(target_os = "linux", target_os = "android"))]
    path: PathBuf,
    #[cfg(not(any(target_os = "linux", target_os = "android")))]
    document: Arc<Value>,
}

impl DictionaryHostOptions {
    fn snapshot(&self) -> Result<Value, CommandError> {
        #[cfg(any(target_os = "linux", target_os = "android"))]
        {
            // Keep the installer-selected path separate from the IBus runtime
            // path; deployments can supply different files for these roles.
            read_runtime_options(&self.path).map_err(|_| CommandError { code: "storage" })
        }
        #[cfg(not(any(target_os = "linux", target_os = "android")))]
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
        #[cfg(any(target_os = "linux", target_os = "android"))]
        let mut document = document;
        #[cfg(any(target_os = "linux", target_os = "android"))]
        if let Some(path) = self.path.as_ref() {
            *document = read_runtime_options(path)?;
        }
        Ok(document.clone())
    }
}

#[cfg(any(target_os = "linux", target_os = "android"))]
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

#[cfg(any(target_os = "linux", target_os = "windows"))]
#[derive(Clone, Default)]
struct DesktopSettingsLinger {
    generation: Arc<AtomicU64>,
    quitting: Arc<AtomicBool>,
}

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
    #[cfg(target_os = "ios")] platform: tauri::State<'_, MobilePlatform<tauri::Wry>>,
    expected_revision: u64,
    preferences: Preferences,
) -> Result<PreferencesSnapshot, CommandError> {
    let store = store.inner().clone();
    let runtime = runtime.inner().clone();
    #[cfg(target_os = "ios")]
    let platform = platform.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        #[cfg(target_os = "ios")]
        let previous = store.load().map_err(CommandError::from)?;
        let snapshot = store
            .save(expected_revision, preferences)
            .map_err(CommandError::from)?;
        #[cfg(target_os = "ios")]
        if let Err(_) = platform.save_keyboard_ai(&ios_keyboard_ai_preferences(
            &snapshot.preferences.ai_assistant,
        )) {
            // Do not leave the canonical Rust document and the keyboard's
            // native mirror describing different AI services. The revision
            // returned by save() is the only revision that can safely roll
            // back the write; a concurrent writer is reported as storage
            // failure rather than overwritten.
            let _ = store.save(snapshot.revision, previous.preferences);
            return Err(CommandError { code: "ai_storage" });
        }
        if clipboard_history_uses_preference(host_platform())
            && !snapshot.preferences.clipboard_history
        {
            store
                .clear_disabled_clipboard_history()
                .map_err(CommandError::from)?;
        }
        sync_runtime_options(&runtime, &snapshot.preferences)
            .map_err(|_| CommandError { code: "storage" })?;
        Ok(snapshot)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[cfg(any(target_os = "ios", test))]
fn ios_keyboard_ai_preferences(
    preferences: &msime_client_core::preferences::AiAssistantPreferences,
) -> IosKeyboardAiPreferences {
    let provider = match preferences.provider.as_str() {
        "everyapi" => "everyAPI",
        "openai" => "openAI",
        "anthropic" => "anthropic",
        "gemini" => "gemini",
        "deepseek" => "deepSeek",
        "qwen" => "qwen",
        "kimi" => "kimi",
        "zhipu" => "zhipu",
        "siliconflow" => "siliconFlow",
        "openrouter" => "openRouter",
        _ => "custom",
    }
    .to_owned();
    let token = reqwest::Url::parse(preferences.endpoint.trim())
        .ok()
        .and_then(|url| {
            if url.scheme() != "https"
                || url.host_str().is_none()
                || !url.username().is_empty()
                || url.password().is_some()
                || url.fragment().is_some()
            {
                return None;
            }
            let origin = format!(
                "https://{}:{}",
                url.host_str()?.to_ascii_lowercase(),
                url.port().unwrap_or(443)
            );
            preferences
                .tokens
                .get(&preferences.provider)
                .or_else(|| preferences.tokens.get(&origin))
                .or_else(|| (!preferences.token.is_empty()).then_some(&preferences.token))
                .cloned()
        })
        .unwrap_or_default();
    let enabled = preferences.enabled
        && !preferences.endpoint.trim().is_empty()
        && !preferences.model.trim().is_empty()
        && !preferences.prompt.trim().is_empty()
        && !token.trim().is_empty();
    IosKeyboardAiPreferences {
        // Rust preferences may intentionally be enabled before the user has
        // supplied a credential. Keep that draft in the canonical store, but
        // clear the native mirror until the keyboard can actually authenticate.
        enabled,
        provider,
        endpoint: preferences.endpoint.clone(),
        model: preferences.model.clone(),
        prompt: if preferences.prompt.trim().is_empty() {
            "请润色以下文字，保持原意，只返回修改后的文字。".to_owned()
        } else {
            preferences.prompt.clone()
        },
        token,
    }
}

#[cfg(any(target_os = "linux", all(test, unix)))]
fn configured_provider_socket(
    document: &Value,
    key: &str,
    environment: &str,
    discovered: &str,
) -> Option<PathBuf> {
    document
        .get(key)
        .and_then(Value::as_str)
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .or_else(|| {
            std::env::var_os(environment)
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
        })
        .or_else(|| discover_session_provider(discovered))
}

#[cfg(any(target_os = "linux", all(test, unix)))]
fn credential_provider_socket(document: &Value, service: &str) -> Option<PathBuf> {
    if service.starts_with("voice.") {
        return resolve_voice_provider_socket(document);
    }
    if service.starts_with("translation.") {
        return configured_provider_socket(
            document,
            "translation_provider_socket",
            "MSIME_TRANSLATION_PROVIDER_SOCKET",
            "translation.sock",
        )
        .or_else(|| {
            configured_provider_socket(
                document,
                "online_provider_socket",
                "MSIME_ONLINE_PROVIDER_SOCKET",
                "online.sock",
            )
        });
    }
    (service == "ai.assistant").then(|| {
        configured_provider_socket(
            document,
            "online_provider_socket",
            "MSIME_ONLINE_PROVIDER_SOCKET",
            "online.sock",
        )
    })?
}

#[tauri::command]
async fn test_api_credential(
    runtime: tauri::State<'_, RuntimeOptionsState>,
    service: String,
    config: Value,
) -> Result<msime_input_runtime::CredentialTestResult, CommandError> {
    #[cfg(target_os = "linux")]
    {
        let runtime = runtime.inner().clone();
        return tauri::async_runtime::spawn_blocking(move || {
            let document = runtime.snapshot().map_err(|_| CommandError {
                code: "unavailable",
            })?;
            let path = credential_provider_socket(&document, &service).ok_or(CommandError {
                code: "unavailable",
            })?;
            UnixSocketProvider::new(path)
                .test_credential(&service, &config)
                .ok_or(CommandError {
                    code: "unavailable",
                })
        })
        .await
        .map_err(|_| CommandError {
            code: "unavailable",
        })?;
    }
    #[cfg(any(target_os = "windows", target_os = "macos"))]
    {
        let _ = runtime;
        let result = tauri::async_runtime::spawn_blocking(move || {
            if service == "voice.asr" {
                if config.get("provider").and_then(Value::as_str) == Some("doubao") {
                    return msime_client_core::credential_doubao::test(
                        &config,
                        &msime_client_core::credential_doubao::WebSocketTransport,
                    );
                }
                return msime_client_core::credential_asr::test(
                    &config,
                    &msime_client_core::credential_asr::HttpTransport,
                );
            }
            if service.starts_with("translation.") {
                let milliseconds = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|duration| duration.as_millis().min(u64::MAX as u128) as u64)
                    .unwrap_or(0);
                return msime_client_core::credential_translation::test(
                    &service,
                    &config,
                    milliseconds,
                    &msime_client_core::credential_translation::HttpTransport,
                );
            }
            msime_client_core::credential_test::test_chat(
                &service,
                &config,
                &msime_client_core::credential_test::HttpsProbeTransport,
            )
        })
        .await
        .map_err(|_| CommandError {
            code: "unavailable",
        })?;
        Ok(msime_input_runtime::CredentialTestResult {
            ok: result.ok,
            message: result.message,
        })
    }
    #[cfg(target_os = "ios")]
    {
        let _ = runtime;
        let result = tauri::async_runtime::spawn_blocking(move || {
            let result = msime_client_core::credential_test::test_chat(
                &service,
                &config,
                &msime_client_core::credential_test::HttpsProbeTransport,
            );
            msime_input_runtime::CredentialTestResult {
                ok: result.ok,
                message: result.message,
            }
        })
        .await
        .map_err(|_| CommandError {
            code: "unavailable",
        })?;
        Ok(result)
    }
    #[cfg(not(any(
        target_os = "linux",
        target_os = "windows",
        target_os = "macos",
        target_os = "ios"
    )))]
    {
        let _ = (runtime, service, config);
        Err(CommandError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn load_custom_skin_library(
    store: tauri::State<'_, CustomSkinLibraryStore>,
) -> Result<Vec<SavedTouchKeyboardSkin>, CommandError> {
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || store.load().map_err(custom_skin_library_error))
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

fn sync_runtime_options(
    runtime: &RuntimeOptionsState,
    preferences: &Preferences,
) -> Result<(), std::io::Error> {
    #[cfg(any(target_os = "linux", target_os = "android"))]
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
    #[cfg(not(any(target_os = "linux", target_os = "android")))]
    {
        let _ = (runtime, preferences);
    }
    Ok(())
}

#[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
fn start_desktop_preferences_monitor(
    app: &tauri::AppHandle,
    store: std::sync::Arc<PreferencesStore>,
    history: Arc<Mutex<ClipboardHistoryStore>>,
) {
    let app = app.clone();
    let _ = std::thread::Builder::new()
        .name("msime-preferences-monitor".to_owned())
        .spawn(move || {
            let mut monitor = desktop_preferences_monitor::Monitor::new(&store);
            loop {
                std::thread::sleep(std::time::Duration::from_millis(750));
                monitor.poll(&app, &store, &history);
            }
        });
}

#[cfg(any(target_os = "linux", target_os = "android"))]
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

/// Keep the host's reason instead of flattening every failure to "storage".
///
/// The host distinguishes three things the user can actually act on - the
/// dictionary is locked by another process, the edit itself was refused, and
/// the store could not be opened - and the page used to print one identical
/// sentence for all of them.
/// Ask the Windows Server to release or retake its Engine sessions.
///
/// Dictionary maintenance needs the exclusive file lock that every session
/// holds a share of, so with the IME in use it fails with "maintenance busy"
/// every time. The Server answers "OK" only once the sessions really are gone,
/// so that reply - not the write succeeding - is what makes it safe to open
/// the dictionaries exclusively.
///
/// The Server also resumes on its own after a deadline, so a settings process
/// that dies mid-import cannot leave input without sessions.
#[cfg(target_os = "windows")]
fn dictionary_maintenance_handshake(verb: &str) -> bool {
    use std::io::{Read, Write};
    const PIPE_NAME: &str = r"\\.\pipe\FanyImeAuxNamedPipe";
    let payload: Vec<u8> = verb
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect();
    for attempt in 0..5 {
        match fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(PIPE_NAME)
        {
            Ok(mut pipe) => {
                if pipe.write_all(&payload).is_err() {
                    return false;
                }
                let mut reply = [0_u8; 8];
                let Ok(read) = pipe.read(&mut reply) else {
                    return false;
                };
                // The Server writes UTF-16LE "OK" and nothing else.
                return reply[..read] == *b"O\x00K\x00";
            }
            Err(_) if attempt < 4 => std::thread::sleep(std::time::Duration::from_millis(20)),
            // No Server listening means no sessions to release, so the lock is
            // already free and the caller should go ahead.
            Err(_) => return verb == "DictionaryQuiesce",
        }
    }
    false
}

fn dictionary_error_code(reason: &str) -> &'static str {
    match reason {
        "dictionary maintenance busy" => "dictionary_busy",
        "dictionary import rejected" => "dictionary_import_rejected",
        "dictionary read rejected" => "dictionary_read_rejected",
        "dictionary pinyin unavailable" => "dictionary_pinyin_unavailable",
        "dictionary access unavailable" => "dictionary_unavailable",
        _ => "storage",
    }
}

#[cfg(any(target_os = "ios", test))]
fn ios_personal_dictionary_action(action: &Value) -> bool {
    matches!(
        action.get("operation").and_then(Value::as_str),
        Some("list" | "edit" | "import_personal" | "export" | "retry" | "dismiss_failure")
    )
}

#[cfg(target_os = "ios")]
fn ios_personal_dictionary_request(request: &Value) -> Result<Value, CommandError> {
    use std::ffi::CStr;
    let bytes = serde_json::to_vec(
        request
            .get("action")
            .ok_or(CommandError { code: "storage" })?,
    )
    .map_err(|_| CommandError { code: "storage" })?;
    if bytes.len() > 1_200_000 {
        return Err(CommandError { code: "storage" });
    }
    let pointer = unsafe { msime_ios_personal_dictionary_request(bytes.as_ptr(), bytes.len()) };
    if pointer.is_null() {
        return Err(CommandError { code: "storage" });
    }
    let response = unsafe { CStr::from_ptr(pointer) }.to_bytes().to_vec();
    unsafe { msime_ios_personal_dictionary_string_free(pointer) };
    let envelope: Value =
        serde_json::from_slice(&response).map_err(|_| CommandError { code: "storage" })?;
    if envelope.get("ok") == Some(&Value::Bool(true)) {
        return envelope
            .get("value")
            .cloned()
            .ok_or(CommandError { code: "storage" });
    }
    let code = match envelope.get("error").and_then(Value::as_str) {
        Some("dictionary_busy") => "dictionary_busy",
        Some("dictionary_conflict") => "dictionary_conflict",
        Some("dictionary_too_many") => "dictionary_too_many",
        Some("dictionary_unavailable") => "dictionary_unavailable",
        Some("dictionary_import_rejected") => "dictionary_import_rejected",
        _ => "storage",
    };
    Err(CommandError { code })
}

#[cfg(target_os = "ios")]
unsafe extern "C" {
    fn msime_ios_personal_dictionary_request(
        request: *const u8,
        length: usize,
    ) -> *mut std::ffi::c_char;
    fn msime_ios_personal_dictionary_string_free(value: *mut std::ffi::c_char);
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
        #[cfg(target_os = "ios")]
        if ios_personal_dictionary_action(&request["action"]) {
            return ios_personal_dictionary_request(&request);
        }
        let bytes = serde_json::to_vec(&request).map_err(|_| CommandError { code: "storage" })?;
        #[cfg(target_os = "android")]
        {
            return msime_host_api::personal_dictionary_request_json(&bytes).map_err(|reason| {
                CommandError {
                    code: dictionary_error_code(&reason),
                }
            });
        }
        #[cfg(not(target_os = "android"))]
        {
            let first = msime_host_api::dictionary_request_json(&bytes);
            // Only the lock is worth a handshake. Every other failure is about
            // the request itself and would fail again with sessions released.
            #[cfg(target_os = "windows")]
            if matches!(&first, Err(reason) if reason == "dictionary maintenance busy")
                && dictionary_maintenance_handshake("DictionaryQuiesce")
            {
                let retried = msime_host_api::dictionary_request_json(&bytes);
                // Resume whatever happened: leaving the IME without
                // sessions because an import failed would be worse than
                // the failure itself.
                let _ = dictionary_maintenance_handshake("DictionaryResume");
                return retried.map_err(|reason| CommandError {
                    code: dictionary_error_code(&reason),
                });
            }
            first.map_err(|reason| CommandError {
                code: dictionary_error_code(&reason),
            })
        }
    })
    .await
    .map_err(|_| CommandError { code: "storage" })?
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tauri::command]
async fn cloud_clipboard_request(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    options: tauri::State<'_, DictionaryHostOptions>,
    action: Value,
) -> Result<Value, CommandError> {
    let _ = (&app, &window);
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
            let configured = configured.or_else(|| {
                std::env::var_os("MSIME_CLOUD_CLIPBOARD_PROVIDER_SOCKET")
                    .and_then(|value| value.into_string().ok())
            });
            #[cfg(target_os = "macos")]
            if configured.is_none() {
                if let Some(result) = app
                    .state::<macos_cloud_clipboard::CloudState>()
                    .request(window.label(), &action)
                {
                    return result;
                }
            }
            let path = configured
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

#[cfg(target_os = "ios")]
#[tauri::command]
async fn cloud_clipboard_request(
    state: tauri::State<'_, ios_account::AccountState>,
    action: Value,
) -> Result<Value, CommandError> {
    msime_host_api::cloud_clipboard::validate_request(&action).map_err(|_| CommandError {
        code: "invalid_cloud_clipboard",
    })?;
    ios_account::cloud_clipboard_request(state, action).await
}

#[cfg(target_os = "android")]
#[tauri::command]
async fn cloud_clipboard_request(
    state: tauri::State<'_, android_account::AccountState>,
    action: Value,
) -> Result<Value, CommandError> {
    msime_host_api::cloud_clipboard::validate_request(&action).map_err(|_| CommandError {
        code: "invalid_cloud_clipboard",
    })?;
    android_account::cloud_clipboard_request(state, action).await
}

#[tauri::command]
fn cloud_clipboard_can_send_text(app: tauri::AppHandle, window: tauri::WebviewWindow) -> bool {
    #[cfg(target_os = "macos")]
    return macos_panel_session::can_submit_clipboard(&app, window.label());
    #[cfg(not(target_os = "macos"))]
    let _ = (app, window);
    #[cfg(not(target_os = "macos"))]
    cfg!(any(target_os = "linux", target_os = "windows"))
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tauri::command]
async fn cloud_dictionary_request(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    options: tauri::State<'_, DictionaryHostOptions>,
    action: Value,
) -> Result<Value, CommandError> {
    let _ = (&app, &window);
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
            let configured = configured.or_else(|| {
                std::env::var_os("MSIME_CLOUD_DICTIONARY_PROVIDER_SOCKET")
                    .and_then(|value| value.into_string().ok())
            });
            #[cfg(target_os = "macos")]
            if configured.is_none() {
                if let Some(result) = app
                    .state::<macos_cloud_dictionary::DictionaryState>()
                    .request(window.label(), &action)
                {
                    return result;
                }
            }
            let path = configured
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

#[cfg(target_os = "ios")]
#[tauri::command]
async fn cloud_dictionary_request(
    state: tauri::State<'_, ios_account::AccountState>,
    action: Value,
) -> Result<Value, CommandError> {
    let request =
        serde_json::from_value::<msime_host_api::cloud_dictionary::CloudDictionaryRequest>(
            action.clone(),
        )
        .map_err(|_| CommandError {
            code: "invalid_cloud_dictionary",
        })?;
    msime_host_api::cloud_dictionary::validate_cloud_request(&request).map_err(|_| {
        CommandError {
            code: "invalid_cloud_dictionary",
        }
    })?;
    ios_account::cloud_dictionary_request(state, action).await
}

#[cfg(target_os = "android")]
#[tauri::command]
async fn cloud_dictionary_request(
    state: tauri::State<'_, android_account::AccountState>,
    action: Value,
) -> Result<Value, CommandError> {
    let request =
        serde_json::from_value::<msime_host_api::cloud_dictionary::CloudDictionaryRequest>(
            action.clone(),
        )
        .map_err(|_| CommandError {
            code: "invalid_cloud_dictionary",
        })?;
    msime_host_api::cloud_dictionary::validate_cloud_request(&request).map_err(|_| {
        CommandError {
            code: "invalid_cloud_dictionary",
        }
    })?;
    android_account::cloud_dictionary_request(state, action).await
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
    unavailable: Vec<&'static str>,
}

fn emoji_category_icon(title: &str) -> &'static str {
    [
        ("Smileys", "😀"),
        ("People", "🧑"),
        ("Animals", "🐾"),
        ("Food", "🍕"),
        ("Travel", "🚗"),
        ("Activities", "🎉"),
        ("Objects", "💡"),
        ("Symbols", "❤"),
        ("Flags", "🏳"),
    ]
    .into_iter()
    .find_map(|(name, icon)| title.contains(name).then_some(icon))
    .unwrap_or("☺")
}

// Reads the real catalog on every desktop host. The Windows build used to hit
// a stub that always failed, so the panel fell back to the compact built-in
// catalog - 97 emoji, 18 kaomoji, 48 symbols - behind a permanent "catalog
// failed to load" banner, and the symbol sub-tabs collapsed to one flat tab
// because only this path fills in each group's parent category.
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
    let mut complete = false;
    for _ in 0..256 {
        let page =
            msime_host_api::local_emoji_catalog_slice(resources, category, offset, PAGE_SIZE)?;
        for item in page.items {
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
                    icon: if category == "kaomoji" {
                        ";-)".to_owned()
                    } else {
                        emoji_category_icon(&title).to_owned()
                    },
                    title,
                    parent: None,
                    items: Vec::new(),
                });
                index
            };
            let group = &mut groups[index];
            group.items.push(EmojiCatalogItem {
                keywords: if item.annotation.is_empty() {
                    item.text.clone()
                } else {
                    item.annotation
                },
                text: item.text,
            });
        }
        if page.complete {
            complete = true;
            break;
        }
        if page.next_offset <= offset {
            return Err("local emoji catalog cursor did not advance");
        }
        offset = page.next_offset;
    }
    if !complete {
        return Err("local emoji catalog exceeds limit");
    }
    Ok(groups
        .into_iter()
        .filter(|group| !group.items.is_empty())
        .collect())
}

#[tauri::command]
async fn load_emoji_catalog(
    state: tauri::State<'_, DictionaryHostOptions>,
) -> Result<EmojiCatalogResponse, CommandError> {
    let options = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let document = options.snapshot()?;
        #[cfg(target_os = "linux")]
        let resource_directory = packaged_emoji_resources(&document).ok_or(CommandError {
            code: "unavailable",
        })?;
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
        let mut unavailable = Vec::new();
        let mut read = |category, name| {
            read_local_emoji_groups(resources, category).unwrap_or_else(|_| {
                unavailable.push(name);
                Vec::new()
            })
        };
        let emoji = read("", "emoji");
        let kaomoji = read("kaomoji", "kaomoji");
        let symbols = read("symbols", "symbols");
        Ok(EmojiCatalogResponse {
            emoji,
            kaomoji,
            symbols,
            unavailable,
        })
    })
    .await
    .map_err(|_| CommandError {
        code: "unavailable",
    })?
}

#[derive(Debug, serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

#[cfg(any(target_os = "macos", test))]
fn macos_input_source_restart_args() -> [&'static str; 5] {
    [
        "-n",
        "-b",
        "app.msime.client.preview.inputmethod",
        "--args",
        "--reregister-input-source",
    ]
}

#[tauri::command]
fn restart_input_method() -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        const PIPE_NAME: &str = r"\\.\pipe\FanyImeAuxNamedPipe";
        let payload = windows_restart_payload();
        for attempt in 0..5 {
            match fs::OpenOptions::new().write(true).open(PIPE_NAME) {
                Ok(mut pipe) => {
                    return pipe.write_all(&payload).map_err(|_| HostActionError {
                        code: "unavailable",
                    });
                }
                Err(_) if attempt < 4 => {
                    std::thread::sleep(std::time::Duration::from_millis(20));
                }
                Err(_) => break,
            }
        }
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("open")
            .args(macos_input_source_restart_args())
            .status()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        status.success().then_some(()).ok_or(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    {
        Err(HostActionError {
            code: "unavailable",
        })
    }
    #[cfg(target_os = "linux")]
    {
        linux_process::run_status("ibus", &["restart"], std::time::Duration::from_secs(3))
            .then_some(())
            .ok_or(HostActionError {
                code: "unavailable",
            })
    }
}

fn windows_restart_payload() -> Vec<u8> {
    "RestartServer"
        .encode_utf16()
        .flat_map(|unit| unit.to_le_bytes())
        .collect()
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
fn sway_workspace_for_container(
    value: &serde_json::Value,
    id: u64,
    workspace: Option<(f64, f64, f64, f64)>,
) -> Option<(f64, f64, f64, f64)> {
    let workspace = if value.get("type").and_then(serde_json::Value::as_str) == Some("workspace") {
        value.get("rect").and_then(|rect| {
            Some((
                rect.get("x")?.as_f64()?,
                rect.get("y")?.as_f64()?,
                rect.get("width")?.as_f64()?,
                rect.get("height")?.as_f64()?,
            ))
        })
    } else {
        workspace
    };
    if value.get("id").and_then(serde_json::Value::as_u64) == Some(id) {
        return workspace;
    }
    for key in ["nodes", "floating_nodes"] {
        if let Some(nodes) = value.get(key).and_then(serde_json::Value::as_array) {
            for node in nodes {
                if let Some(rect) = sway_workspace_for_container(node, id, workspace) {
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
fn panel_position(state: &PanelInputState, width: f64, height: f64) -> Option<tauri::Position> {
    let target = state.0.lock().ok()?.clone()?;
    let physical = matches!(&target, PanelInputTarget::X11(_));
    let read = |program: &str, arguments: &[&str], limit: usize| {
        linux_process::read_text(program, arguments, limit, std::time::Duration::from_secs(1))
    };
    let mut logical_workspace = None;
    let rect = match target {
        PanelInputTarget::X11(window) => read(
            "xdotool",
            &["getwindowgeometry", "--shell", window.as_str()],
            4096,
        )
        .and_then(|output| parse_xdotool_geometry(&output)),
        PanelInputTarget::Sway(id) => read("swaymsg", &["-t", "get_tree", "-r"], 1024 * 1024)
            .and_then(|output| serde_json::from_str::<serde_json::Value>(&output).ok())
            .and_then(|tree| {
                logical_workspace = sway_workspace_for_container(&tree, id, None);
                sway_rect_for_container(&tree, id)
            }),
        PanelInputTarget::Wayland | PanelInputTarget::Ydotool => None,
    }?;
    if ![rect.0, rect.1, rect.2, rect.3]
        .iter()
        .all(|value| value.is_finite())
        || rect.2 <= 0.0
        || rect.3 <= 0.0
    {
        return None;
    }
    let mut x = rect.0 + (rect.2 - width) / 2.0;
    let mut y = rect.1 + rect.3 + 16.0;
    if let Some((left, top, workspace_width, workspace_height)) = logical_workspace {
        if [left, top, workspace_width, workspace_height]
            .iter()
            .all(|value| value.is_finite())
            && workspace_width > 0.0
            && workspace_height > 0.0
        {
            x = x.clamp(left, left + (workspace_width - width).max(0.0));
            y = y.clamp(top, top + (workspace_height - height).max(0.0));
        }
    }
    if !x.is_finite() || !y.is_finite() {
        return None;
    }
    Some(if physical {
        tauri::Position::Physical(tauri::PhysicalPosition::new(
            x.round() as i32,
            y.round() as i32,
        ))
    } else {
        tauri::Position::Logical(tauri::LogicalPosition::new(x, y))
    })
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
    Err(HostActionError {
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
    let arguments: Vec<&str> = args.iter().map(String::as_str).collect();
    linux_process::run_status("ydotool", &arguments, std::time::Duration::from_secs(3))
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
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
        let results: Vec<serde_json::Value> =
            serde_json::from_str(&reply).map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        if results.is_empty()
            || results.iter().any(|result| {
                result.get("success").and_then(serde_json::Value::as_bool) != Some(true)
            })
        {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        // A successful command is insufficient when the window disappeared or
        // focus changed. Confirm the actual destination before virtual input.
        let tree = linux_process::read_text(
            "swaymsg",
            &["-t", "get_tree", "-r"],
            1024 * 1024,
            std::time::Duration::from_secs(1),
        )
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
        let tree: serde_json::Value = serde_json::from_str(&tree).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        if focused_sway_container(&tree) != Some(*id) {
            return Err(HostActionError {
                code: "unavailable",
            });
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
    linux_process::read_text("wtype", &arguments, 64, std::time::Duration::from_secs(3))
        .map(|_| ())
        .ok_or(HostActionError {
            code: "unavailable",
        })
}

#[cfg(target_os = "linux")]
fn release_panel_focus(
    app: &tauri::AppHandle,
    target: &PanelInputTarget,
) -> Result<(), HostActionError> {
    if !matches!(
        target,
        PanelInputTarget::Wayland | PanelInputTarget::Ydotool
    ) {
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
    .ok_or(HostActionError {
        code: "unavailable",
    })
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
    let literal_transfer = text
        .chars()
        .any(|character| matches!(character, '\n' | '\r' | '\t'))
        || (matches!(target, PanelInputTarget::Ydotool) && !text.is_ascii());
    if literal_transfer {
        if !write_linux_clipboard(text) {
            return Err(HostActionError {
                code: "unavailable",
            });
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
            &[
                "windowactivate",
                "--sync",
                window.as_str(),
                "type",
                "--delay",
                "0",
                "--file",
                "-",
            ],
            text.as_bytes(),
            std::time::Duration::from_secs(3),
        )
        .then_some(())
        .ok_or(HostActionError {
            code: "unavailable",
        });
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
    sent.then_some(()).ok_or(HostActionError {
        code: "unavailable",
    })
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn record_panel_typing_statistics(store: &TypingStatisticsStore, text: &str, source: TypingSource) {
    let day = time::OffsetDateTime::now_local()
        .unwrap_or_else(|_| time::OffsetDateTime::now_utc())
        .date();
    let day = format!(
        "{:04}-{:02}-{:02}",
        day.year(),
        u8::from(day.month()),
        day.day()
    );
    let _ = store.record(text, source, &day);
}

#[cfg(target_os = "linux")]
async fn send_panel_text(
    app: tauri::AppHandle,
    state: &tauri::State<'_, PanelInputState>,
    typing_statistics: &tauri::State<'_, TypingStatisticsState>,
    text: String,
    source: TypingSource,
) -> Result<(), HostActionError> {
    if text.is_empty()
        || text.len() > 4096
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    {
        return Err(HostActionError {
            code: "invalid_text",
        });
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
    let typing_statistics = typing_statistics.0.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let result = send_panel_text_to_target(&app, &target, &text);
        if result.is_ok() {
            record_panel_typing_statistics(&typing_statistics, &text, source);
        }
        result
    })
    .await
    .map_err(|_| HostActionError {
        code: "unavailable",
    })?
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
    voice_output::submit(text, commit_mode, |mode, text| match mode {
        // An independent Tauri panel has no IBus input context. Both input
        // modes therefore use the remembered Linux editor target, while the
        // in-engine voice entry continues to commit through IBus directly.
        voice_output::OutputMode::Tsf | voice_output::OutputMode::SendInput => {
            send_panel_text_to_target(app, target, text).is_ok()
        }
        voice_output::OutputMode::Clipboard => {
            if !write_linux_clipboard(text) {
                return false;
            }
            std::thread::sleep(std::time::Duration::from_millis(30));
            send_panel_ctrl_v(app, target).is_ok()
        }
    })
    .map_err(|error| HostActionError {
        code: match error {
            voice_output::OutputError::InvalidText => "invalid_text",
            voice_output::OutputError::TsfRequiresServer => "tsf_requires_server",
            voice_output::OutputError::Unavailable => "unavailable",
        },
    })
}

// Windows panels are ordinary Tauri windows that never activate, so the host
// injects input on their behalf through the Windows host layer; this shell
// itself stays free of unsafe code.

#[cfg(target_os = "windows")]
fn remember_panel_input_target(
    state: &tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    // Editable panels invoke this again after mounting. Do not replace the
    // original editor with our own newly focused webview.
    if !msime_host_windows::foreground_is_external() {
        return state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .as_ref()
            .map(|_| ())
            .ok_or(HostActionError {
                code: "unavailable",
            });
    }
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
    keyboard_panel: bool,
) -> Result<(), HostActionError> {
    request.validate().map_err(|_| HostActionError {
        code: "invalid_key",
    })?;
    // The on-screen keyboard follows whatever the user is typing into now, as
    // the reference does with RememberInputTargetWindow on every press. The
    // panel is WS_EX_NOACTIVATE, so the foreground genuinely is the editor;
    // re-focusing the handle captured when the panel opened sent every key to
    // a window the user may have left several clicks ago. Other panels keep
    // their original destination, which is what being edited implies.
    if !keyboard_panel || !msime_host_windows::foreground_is_external() {
        focused_panel_target(state)?;
    }
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
fn windows_panel_position(width: f64, height: f64) -> Option<tauri::Position> {
    msime_host_windows::work_area().map(|area| {
        let (x, y) = area.bottom_center(width, height);
        tauri::Position::Physical(tauri::PhysicalPosition::new(
            x.round() as i32,
            y.round() as i32,
        ))
    })
}

fn launch_route_from_args(args: &[String]) -> Option<SurfaceRoute> {
    args.iter().find_map(|argument| {
        argument
            .strip_prefix("--route=")
            .and_then(|route| SurfaceRoute::parse(route).ok())
    })
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn cancel_settings_linger(app: &tauri::AppHandle) {
    if let Some(state) = app.try_state::<DesktopSettingsLinger>() {
        state.generation.fetch_add(1, Ordering::AcqRel);
    }
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn activate_desktop_surface(app: &tauri::AppHandle, route: SurfaceRoute) {
    cancel_settings_linger(app);
    if let Some(surface) = route.panel() {
        let state = app.state::<PanelInputState>();
        #[cfg(target_os = "linux")]
        let position = {
            let _ = remember_panel_input_target(&state, true);
            panel_position(&state, f64::from(surface.width), f64::from(surface.height))
        };
        #[cfg(target_os = "windows")]
        let position = {
            let _ = remember_panel_input_target(&state);
            windows_panel_position(f64::from(surface.width), f64::from(surface.height))
        };
        let _ = open_panel_window(
            app,
            surface.label,
            surface.query,
            surface.title,
            f64::from(surface.width),
            f64::from(surface.height),
            position,
        );
        return;
    }
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
    let page = route
        .settings_category()
        .map(|category| category.as_str())
        .unwrap_or_default();
    let _ = app.emit("settings-route", page);
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
        request.validate().map_err(|_| HostActionError {
            code: "invalid_key",
        })?;
        // The non-focusable keyboard follows the editor the user is typing
        // into now, like Windows RememberInputTargetWindow on each key press.
        // Other panels retain their original destination while being edited.
        let target = if window.label() == "keyboard-panel" {
            None
        } else {
            Some(
                state
                    .0
                    .lock()
                    .map_err(|_| HostActionError {
                        code: "unavailable",
                    })?
                    .clone()
                    .ok_or(HostActionError {
                        code: "unavailable",
                    })?,
            )
        };
        return tauri::async_runtime::spawn_blocking(move || {
            let target = match target {
                Some(target) => target,
                None => capture_panel_input_target()?,
            };
            send_panel_key(&app, target, request)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    }
    #[cfg(target_os = "windows")]
    return send_panel_key_windows(&state, request, window.label() == "keyboard-panel");
    #[cfg(target_os = "macos")]
    {
        let _ = state;
        request.validate().map_err(|_| HostActionError {
            code: "invalid_key",
        })?;
        // Only the non-focusable keyboard follows the current editor. Other
        // panels will use their own captured input-session handoff.
        if window.label() != "keyboard-panel" {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        let (send, received) = std::sync::mpsc::sync_channel(1);
        app.run_on_main_thread(move || {
            let _ = send.send(msime_host_macos::send_keyboard_key(&request));
        })
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        tauri::async_runtime::spawn_blocking(move || {
            received
                .recv()
                .unwrap_or(false)
                .then_some(())
                .ok_or(HostActionError {
                    code: "unavailable",
                })
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
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
    #[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
    #[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
    // Windows ships a recognizer with the language pack, and it is the only one
    // a stock machine has: the packaged Engine model is optional in the
    // installer. Try it first, and fall through to the model when Windows has
    // no Chinese handwriting feature installed.
    #[cfg(windows)]
    {
        let strokes: Vec<msime_host_windows::ink::Stroke> = query
            .strokes
            .iter()
            .map(|stroke| stroke.iter().map(|point| (point.x, point.y)).collect())
            .collect();
        let recognized = tauri::async_runtime::spawn_blocking(move || {
            msime_host_windows::ink::recognize(&strokes)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
        match recognized {
            Ok(candidates) if !candidates.is_empty() => {
                let result = HandwritingRecognitionResult { candidates };
                result.validate().map_err(|_| HostActionError {
                    code: "invalid_stroke",
                })?;
                return Ok(result);
            }
            // Recognized nothing, or Windows has no Chinese recognizer. Either
            // way the packaged model below is still worth asking.
            _ => {}
        }
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
        .or_else(|| {
            std::env::var_os("MSIME_HANDWRITING_MODEL")
                .filter(|value| !value.is_empty())
                .map(PathBuf::from)
        })
        .or_else(|| {
            #[cfg(target_os = "macos")]
            {
                std::env::current_exe()
                    .ok()
                    .and_then(|executable| macos_handwriting::bundled_model(&executable))
            }
            #[cfg(not(target_os = "macos"))]
            {
                None
            }
        })
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

#[cfg(any(target_os = "ios", test))]
#[derive(Debug, PartialEq, Eq)]
struct IosVoiceProviderConfiguration {
    provider: String,
    endpoint: String,
    model: String,
    token: String,
    headers: Vec<IosVoiceRequestHeader>,
    enable_itn: bool,
    enable_punctuation: bool,
    enable_ddc: bool,
    boosting_table_id: String,
}

#[cfg(any(target_os = "ios", test))]
fn ios_voice_provider_configuration(
    preferences: &Preferences,
) -> Result<IosVoiceProviderConfiguration, HostActionError> {
    let voice = &preferences.voice_input;
    let (default_endpoint, default_model) = match voice.asr_provider.as_str() {
        "doubao" => (
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async",
            "",
        ),
        "openai" => (
            "https://api.openai.com/v1/audio/transcriptions",
            "whisper-1",
        ),
        "siliconflow" => (
            "https://api.siliconflow.cn/v1/audio/transcriptions",
            "FunAudioLLM/SenseVoiceSmall",
        ),
        "groq" => (
            "https://api.groq.com/openai/v1/audio/transcriptions",
            "whisper-large-v3-turbo",
        ),
        _ => {
            return Err(HostActionError {
                code: "unsupported_voice",
            });
        }
    };
    let endpoint = match voice.asr_endpoint.trim() {
        "" => default_endpoint,
        value => value,
    };
    let model = match voice.asr_model.trim() {
        "" => default_model,
        value => value,
    };
    let token = match voice.asr_token.trim() {
        "" => voice
            .asr_tokens
            .get(&voice.asr_provider)
            .map(String::as_str)
            .unwrap_or("")
            .trim(),
        value => value,
    };
    let boosting_table_id = voice.doubao_boosting_table_id.trim();
    if endpoint.len() > 2_048
        || model.len() > 512
        || token.len() > 16 * 1024
        || boosting_table_id.len() > 4_096
        || endpoint.chars().any(char::is_control)
        || model.chars().any(char::is_control)
        || token.chars().any(char::is_control)
        || boosting_table_id.chars().any(char::is_control)
    {
        return Err(HostActionError {
            code: "invalid_voice",
        });
    }
    let headers = if voice.asr_provider == "doubao" {
        let resource_id = match voice.asr_resource_id.trim() {
            "" => "volc.seedasr.sauc.duration",
            value => value,
        };
        msime_client_core::doubao_auth::headers(
            &voice.doubao_auth_mode,
            &voice.asr_app_key,
            token,
            resource_id,
        )
        .ok_or(HostActionError {
            code: "invalid_voice",
        })?
        .into_iter()
        .map(|(name, value)| IosVoiceRequestHeader {
            name: name.into(),
            value,
        })
        .collect()
    } else {
        Vec::new()
    };
    Ok(IosVoiceProviderConfiguration {
        provider: voice.asr_provider.clone(),
        endpoint: endpoint.to_owned(),
        model: model.to_owned(),
        token: if voice.asr_provider == "doubao" {
            String::new()
        } else {
            token.to_owned()
        },
        headers,
        enable_itn: voice.doubao_enable_itn,
        enable_punctuation: voice.doubao_enable_punc,
        enable_ddc: voice.doubao_enable_ddc,
        boosting_table_id: boosting_table_id.to_owned(),
    })
}

#[cfg(any(unix, windows))]
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

#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
fn utf8_prefix(value: &str, max_bytes: usize) -> &str {
    let mut end = value.len().min(max_bytes);
    while !value.is_char_boundary(end) {
        end -= 1;
    }
    &value[..end]
}

#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
        "doubao_auth_mode",
        "asr_model",
        "asr_resource_id",
        "polish_provider",
        "polish_model",
        "polish_prompt_id",
        "doubao_boosting_table_id",
    ] {
        if let Some(value) = voice.get(key).and_then(Value::as_str) {
            if key == "doubao_auth_mode" && !matches!(value, "api_key" | "legacy") {
                continue;
            }
            options.insert(
                key.to_owned(),
                Value::String(utf8_prefix(value, 512).to_owned()),
            );
        }
    }
    let preset = voice
        .get("polish_prompt_id")
        .and_then(Value::as_str)
        .unwrap_or("cleanup");
    let prompt_key = match preset {
        "custom" | "custom_1" => Some("polish_prompt_custom_1"),
        "custom_2" => Some("polish_prompt_custom_2"),
        "custom_3" => Some("polish_prompt_custom_3"),
        _ => None,
    };
    if let Some(key) = prompt_key {
        let mut prompt = voice.get(key).and_then(Value::as_str).unwrap_or("");
        if prompt.is_empty() && key == "polish_prompt_custom_1" {
            prompt = voice
                .get("polish_prompt")
                .and_then(Value::as_str)
                .unwrap_or("");
        }
        if prompt.len() > 8192 {
            return Err(HostActionError {
                code: "invalid_voice",
            });
        }
        if !prompt.is_empty() {
            options.insert(key.to_owned(), Value::String(prompt.to_owned()));
        }
    }
    Ok(Value::Object(options))
}

// Resolve on each request so services started after the panel remain discoverable.
#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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

#[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
    #[cfg(windows)]
    let _ = (&runtime, &store);
    #[cfg(target_os = "ios")]
    let _ = &runtime;
    #[cfg(target_os = "android")]
    let _ = (&runtime, &store);
    #[cfg(not(any(unix, windows)))]
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
    #[cfg(windows)]
    {
        windows_voice::recognize(app, request).await
    }
    #[cfg(target_os = "android")]
    {
        let platform = app
            .state::<AndroidVoicePlatform<tauri::Wry>>()
            .inner()
            .clone();
        let text = platform
            .recognize_voice(&request.request_id, &request.language)
            .await
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        return Ok(VoiceRecognitionResult { text });
    }
    #[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
                document["preferences"] =
                    serde_json::to_value(preferences.preferences).map_err(|_| HostActionError {
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
                let _ = worker_app.emit(
                    "voice-update",
                    VoiceRecognitionUpdate {
                        text: String::new(),
                        request_id: session.request_id.clone(),
                        final_result: false,
                        phase: Some(phase.to_owned()),
                        level: None,
                    },
                );
            };
            let mut level = |level: f32| {
                if session.cancelled.load(std::sync::atomic::Ordering::Relaxed) {
                    return;
                }
                let _ = worker_app.emit(
                    "voice-update",
                    VoiceRecognitionUpdate {
                        text: String::new(),
                        request_id: session.request_id.clone(),
                        final_result: false,
                        phase: None,
                        level: Some(level),
                    },
                );
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
    #[cfg(target_os = "ios")]
    {
        let store = store.inner().clone();
        let configuration = tauri::async_runtime::spawn_blocking(move || {
            let snapshot = store.load().map_err(|_| HostActionError {
                code: "unavailable",
            })?;
            ios_voice_provider_configuration(&snapshot.preferences)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })??;
        let request_id = request.request_id;
        let _ = app.emit(
            "voice-update",
            VoiceRecognitionUpdate {
                text: String::new(),
                request_id: request_id.clone(),
                final_result: false,
                phase: Some("recording".into()),
                level: None,
            },
        );
        let platform = app.state::<MobilePlatform<tauri::Wry>>().inner().clone();
        let response = platform
            .recognize_voice(IosVoiceTranscriptionRequest {
                request_id,
                provider: configuration.provider,
                endpoint: configuration.endpoint,
                model: configuration.model,
                token: configuration.token,
                headers: configuration.headers,
                enable_itn: configuration.enable_itn,
                enable_punctuation: configuration.enable_punctuation,
                enable_ddc: configuration.enable_ddc,
                boosting_table_id: configuration.boosting_table_id,
            })
            .await
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        Ok(VoiceRecognitionResult {
            text: response.text,
        })
    }
    #[cfg(not(any(unix, windows)))]
    {
        let _ = (request, runtime);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn stop_voice(app: tauri::AppHandle, request_id: String) -> Result<(), HostActionError> {
    #[cfg(target_os = "ios")]
    {
        app.state::<MobilePlatform<tauri::Wry>>()
            .stop_voice(&request_id)
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        let _ = app.emit(
            "voice-update",
            VoiceRecognitionUpdate {
                text: String::new(),
                request_id,
                final_result: false,
                phase: Some("recognizing".into()),
                level: None,
            },
        );
        Ok(())
    }
    #[cfg(target_os = "android")]
    {
        app.state::<AndroidVoicePlatform<tauri::Wry>>()
            .stop_voice(&request_id)
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    }
    #[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
        let sessions = app.state::<voice_sessions::VoiceSessions>();
        let _ = sessions.stop(&request_id);
        Ok(())
    }
}

#[tauri::command]
fn cancel_voice(app: tauri::AppHandle, request_id: Option<String>) -> Result<(), HostActionError> {
    #[cfg(target_os = "ios")]
    {
        app.state::<MobilePlatform<tauri::Wry>>()
            .cancel_voice(request_id.as_deref())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    }
    #[cfg(target_os = "android")]
    {
        app.state::<AndroidVoicePlatform<tauri::Wry>>()
            .cancel_voice(request_id.as_deref())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    }
    #[cfg(all(unix, not(any(target_os = "ios", target_os = "android"))))]
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
        // The Windows worker observes cancellation during I/O, drains it and
        // closes its connection; the Server cancels only that review session.
        let sessions = app.state::<voice_sessions::VoiceSessions>();
        let _ = sessions.cancel(request_id.as_deref());
        Ok(())
    }
}

#[tauri::command]
async fn submit_handwriting_candidate(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    state: tauri::State<'_, PanelInputState>,
    typing_statistics: tauri::State<'_, TypingStatisticsState>,
    candidate: String,
) -> Result<(), HostActionError> {
    let _ = (&window, &typing_statistics, &state);
    #[cfg(target_os = "linux")]
    {
        msime_client_core::panels::validate_candidate(&candidate).map_err(|_| HostActionError {
            code: "invalid_text",
        })?;
        return send_panel_text(
            app,
            &state,
            &typing_statistics,
            candidate,
            TypingSource::Handwriting,
        )
        .await;
    }
    // Recognition without a way to commit is half a panel: Windows could
    // produce candidates and then refuse to insert the one the user picked.
    #[cfg(target_os = "windows")]
    {
        // Windows panels inject through the host rather than the runtime, so
        // they do not pass through the typing counter, matching send_text.
        let _ = (&app, &typing_statistics);
        msime_client_core::panels::validate_candidate(&candidate).map_err(|_| HostActionError {
            code: "invalid_text",
        })?;
        send_panel_text_windows(&state, &candidate)
    }
    #[cfg(target_os = "macos")]
    return macos_panel_session::submit(app, window, candidate).await;
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
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
    window: tauri::WebviewWindow,
    state: tauri::State<'_, PanelInputState>,
    typing_statistics: tauri::State<'_, TypingStatisticsState>,
    text: String,
) -> Result<(), HostActionError> {
    let _ = (&app, &window, &state);
    let _ = &typing_statistics;
    #[cfg(target_os = "linux")]
    return send_panel_text(app, &state, &typing_statistics, text, TypingSource::Unknown).await;
    #[cfg(target_os = "windows")]
    return send_panel_text_windows(&state, &text);
    #[cfg(target_os = "macos")]
    return macos_panel_session::submit(app, window, text).await;
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    {
        let _ = (app, state, text);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn supports_clipboard_paste() -> bool {
    cfg!(any(target_os = "linux", target_os = "windows"))
}

#[tauri::command]
async fn paste_clipboard_text(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
    text: String,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        if text.is_empty()
            || text.len() > msime_client_core::clipboard::MAX_TEXT_BYTES
            || text.contains('\0')
        {
            return Err(HostActionError {
                code: "invalid_text",
            });
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
            if !write_linux_clipboard(&text) {
                return Err(HostActionError {
                    code: "unavailable",
                });
            }
            send_panel_ctrl_v(&app, &target)
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
    }
    #[cfg(target_os = "windows")]
    {
        if text.is_empty()
            || text.len() > msime_client_core::clipboard::MAX_TEXT_BYTES
            || text.contains('\0')
        {
            return Err(HostActionError {
                code: "invalid_text",
            });
        }
        let target = state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .ok_or(HostActionError {
                code: "unavailable",
            })?
            .0;
        return tauri::async_runtime::spawn_blocking(move || {
            msime_host_windows::paste_text(target, &text)
                .then_some(())
                .ok_or(HostActionError {
                    code: "unavailable",
                })
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    }
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    {
        let _ = (app, state, text);
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
async fn send_voice_text(
    app: tauri::AppHandle,
    window: tauri::WebviewWindow,
    state: tauri::State<'_, PanelInputState>,
    typing_statistics: tauri::State<'_, TypingStatisticsState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    text: String,
) -> Result<(), HostActionError> {
    #[cfg(not(target_os = "macos"))]
    let _ = &window;
    #[cfg(target_os = "macos")]
    let _ = (&state, &typing_statistics, &store);
    #[cfg(target_os = "windows")]
    {
        let _ = app;
        let target = state
            .0
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .as_ref()
            .map(|target| target.0)
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        let store = store.inner().clone();
        let statistics = typing_statistics.0.clone();
        tauri::async_runtime::spawn_blocking(move || {
            let mode = store
                .load()
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })?
                .preferences
                .voice_input
                .commit_mode;
            voice_output::submit(&text, &mode, |mode, text| match mode {
                // The TSF mode must use the Server's active-client/epoch lease;
                // do not bypass that boundary with an unacknowledged fallback.
                voice_output::OutputMode::Tsf => false,
                voice_output::OutputMode::SendInput => {
                    msime_host_windows::focus_external(target)
                        && msime_host_windows::send_text(text)
                }
                voice_output::OutputMode::Clipboard => {
                    msime_host_windows::paste_voice_text(target, text)
                }
            })
            .map_err(|error| HostActionError {
                code: match error {
                    voice_output::OutputError::InvalidText => "invalid_text",
                    voice_output::OutputError::TsfRequiresServer => "tsf_requires_server",
                    voice_output::OutputError::Unavailable => "unavailable",
                },
            })?;
            record_panel_typing_statistics(&statistics, &text, TypingSource::Voice);
            Ok(())
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
    }
    #[cfg(target_os = "linux")]
    {
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
        let store = store.inner().clone();
        let typing_statistics = typing_statistics.0.clone();
        return tauri::async_runtime::spawn_blocking(move || {
            let commit_mode = store
                .load()
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })?
                .preferences
                .voice_input
                .commit_mode;
            let result = send_panel_voice_text(&app, &target, &text, &commit_mode);
            if result.is_ok() {
                record_panel_typing_statistics(&typing_statistics, &text, TypingSource::Voice);
            }
            result
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    }
    #[cfg(target_os = "macos")]
    return macos_panel_session::submit(app, window, text).await;
    #[cfg(not(any(target_os = "linux", target_os = "windows", target_os = "macos")))]
    {
        #[cfg(target_os = "ios")]
        {
            let platform = app
                .try_state::<MobilePlatform<tauri::Wry>>()
                .ok_or(HostActionError {
                    code: "unavailable",
                })?
                .inner()
                .clone();
            platform
                .save_voice_text(&text)
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })?;
            let _ = (state, typing_statistics, store);
            Ok(())
        }
        #[cfg(target_os = "android")]
        {
            let platform = app
                .try_state::<AndroidVoicePlatform<tauri::Wry>>()
                .ok_or(HostActionError {
                    code: "unavailable",
                })?
                .inner()
                .clone();
            platform
                .save_voice_text(&text)
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })?;
            let _ = (state, typing_statistics, store);
            Ok(())
        }
        #[cfg(not(any(target_os = "ios", target_os = "android")))]
        {
            let _ = (app, state, typing_statistics, store, text);
            Err(HostActionError {
                code: "unavailable",
            })
        }
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
    url.strip_prefix("https://")
        .is_some_and(|rest| !rest.is_empty() && rest.as_bytes()[0] != b'/')
        && url.starts_with("https://")
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
    {
        return linux_process::run_status(
            "xdg-open",
            &[url.as_str()],
            std::time::Duration::from_secs(3),
        )
        .then_some(())
        .ok_or(HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(target_os = "windows")]
    let result = std::process::Command::new("cmd")
        .args(["/C", "start", ""])
        .arg(&url)
        .status();
    #[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
    let result: Result<std::process::ExitStatus, std::io::Error> =
        Err(std::io::Error::other("unsupported"));
    #[cfg(not(target_os = "linux"))]
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

#[cfg(target_os = "linux")]
fn visible_panel_position(
    window: &tauri::WebviewWindow,
    position: tauri::Position,
    width: f64,
    height: f64,
) -> tauri::Position {
    // X11 geometry is physical. Do not reinterpret Sway's logical coordinates
    // using a monitor scale factor from a different coordinate space.
    let tauri::Position::Physical(point) = position else {
        return position;
    };
    let Ok(monitors) = window.available_monitors() else {
        return position;
    };
    let x = f64::from(point.x);
    let y = f64::from(point.y);
    // panel_position used the logical requested width. Recover the editor's
    // physical center before choosing a monitor and applying its scale.
    let center_x = x + width / 2.0;
    let distance = |monitor: &tauri::Monitor| {
        let area = monitor.work_area();
        let left = f64::from(area.position.x);
        let top = f64::from(area.position.y);
        let dx = center_x - center_x.clamp(left, left + f64::from(area.size.width));
        let dy = y - y.clamp(top, top + f64::from(area.size.height));
        dx * dx + dy * dy
    };
    let Some(monitor) = monitors
        .iter()
        .filter(|monitor| monitor.work_area().size.width > 0 && monitor.work_area().size.height > 0)
        .min_by(|left, right| distance(left).total_cmp(&distance(right)))
    else {
        return position;
    };
    let scale = monitor.scale_factor();
    if !scale.is_finite() || scale <= 0.0 {
        return position;
    }
    let x = center_x - width * scale / 2.0;
    let area = monitor.work_area();
    let left = f64::from(area.position.x);
    let top = f64::from(area.position.y);
    let right = left + (f64::from(area.size.width) - width * scale).max(0.0);
    let bottom = top + (f64::from(area.size.height) - height * scale).max(0.0);
    tauri::Position::Physical(tauri::PhysicalPosition::new(
        x.clamp(left, right).round() as i32,
        y.clamp(top, bottom).round() as i32,
    ))
}

fn open_panel_window(
    app: &tauri::AppHandle,
    label: &'static str,
    route: &'static str,
    title: &'static str,
    width: f64,
    height: f64,
    position: Option<tauri::Position>,
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
            #[cfg(target_os = "macos")]
            if label == "keyboard-panel" {
                return macos_keyboard::show(&window).map_err(|_| HostActionError {
                    code: "unavailable",
                });
            }
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if let Some(position) = position {
                #[cfg(target_os = "linux")]
                let position = visible_panel_position(&window, position, width, height);
                let _ = window.set_position(position);
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
        let builder = WebviewWindowBuilder::new(
            app,
            label,
            WebviewUrl::App(format!("index.html?panel={route}").into()),
        )
        .title(title);
        let window = builder
            .inner_size(width, height)
            .visible(false)
            .focused(false)
            .focusable(accepts_focus)
            .min_inner_size(width, height)
            .resizable(false)
            .decorations(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .build()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?;
        if let Some(position) = position {
            #[cfg(target_os = "linux")]
            let position = visible_panel_position(&window, position, width, height);
            let _ = window.set_position(position);
        }
        #[cfg(target_os = "macos")]
        if label == "keyboard-panel" {
            return macos_keyboard::show(&window).map_err(|_| HostActionError {
                code: "unavailable",
            });
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
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
    let _ = &state;
    #[cfg(target_os = "linux")]
    let position = {
        let _ = remember_panel_input_target(&state, true);
        panel_position(&state, 620.0, 520.0)
    };
    #[cfg(target_os = "windows")]
    let position = {
        let _ = remember_panel_input_target(&state);
        windows_panel_position(620.0, 520.0)
    };
    #[cfg(not(any(target_os = "linux", target_os = "windows")))]
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

#[tauri::command]
fn open_cloud_clipboard_panel(
    app: tauri::AppHandle,
    state: tauri::State<'_, PanelInputState>,
) -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        let _ = remember_panel_input_target(&state, true);
        let position = windows_panel_position(560.0, 560.0);
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
        let _ = remember_panel_input_target(&state, true);
        let position = windows_panel_position(760.0, 700.0);
        open_panel_window(
            &app,
            "cloud-dictionary-panel",
            "cloud-dictionary",
            "水杉云词库",
            760.0,
            700.0,
            position,
        )
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
            | "clipboard-panel"
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
    #[cfg(target_os = "macos")]
    if matches!(label.as_str(), "emoji-panel" | "handwriting-panel") {
        let window = app.get_webview_window(&label).ok_or(HostActionError {
            code: "unavailable",
        })?;
        return macos_panel_session::close(&app, window);
    }
    #[cfg(target_os = "macos")]
    if label == "keyboard-panel" {
        let window = app.get_webview_window(&label).ok_or(HostActionError {
            code: "unavailable",
        })?;
        return macos_keyboard::close(&window).map_err(|_| HostActionError {
            code: "unavailable",
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
                | "clipboard-panel"
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
) -> Result<Vec<ClipboardHistoryEntry>, HostActionError> {
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
) -> Result<Vec<ClipboardHistoryEntry>, HostActionError> {
    if clipboard_history_uses_preference(host_platform()) && !clipboard_enabled(store)? {
        return Ok(Vec::new());
    }
    let mut history = state.0.lock().map_err(|_| HostActionError {
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
async fn set_clipboard_history_pinned(
    text: String,
    pinned: bool,
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
            .set_pinned(&text, pinned)
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

fn clear_clipboard_history_blocking(state: &ClipboardHistoryState) -> Result<(), HostActionError> {
    #[cfg(target_os = "ios")]
    {
        let state_root = std::env::var_os("MSIME_CLIENT_STATE_DIR")
            .map(PathBuf::from)
            .filter(|path| path.is_absolute())
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        let root = state_root.parent().ok_or(HostActionError {
            code: "unavailable",
        })?;
        let _ = state;
        return msime_host_api::clear_mobile_clipboard_history(root).map_err(|_| HostActionError {
            code: "unavailable",
        });
    }
    #[cfg(not(target_os = "ios"))]
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
) -> Result<Vec<ClipboardHistoryEntry>, HostActionError> {
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
) -> Result<Vec<ClipboardHistoryEntry>, HostActionError> {
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
    store
        .capture_clipboard_text(text)
        .map_err(|_| HostActionError {
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

async fn copy_text_impl(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    #[cfg(target_os = "android")] account: tauri::State<'_, android_account::AccountState>,
    #[cfg(target_os = "ios")] platform: tauri::State<'_, MobilePlatform<tauri::Wry>>,
) -> Result<(), HostActionError> {
    let state = state.inner().clone();
    let store = store.inner().clone();
    #[cfg(target_os = "android")]
    {
        if text.is_empty() || text.encode_utf16().count() > 4000 || text.contains('\0') {
            return Err(HostActionError {
                code: "invalid_text",
            });
        }
        let plugin = account.platform.clone();
        let clipboard_text = text.clone();
        tauri::async_runtime::spawn_blocking(move || {
            plugin
                .run_mobile_plugin::<()>("copyText", serde_json::json!({ "text": clipboard_text }))
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })??;
        if clipboard_enabled(&store)? {
            store
                .capture_clipboard_text(text)
                .map_err(|_| HostActionError {
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
        return Ok(());
    }
    #[cfg(target_os = "ios")]
    {
        let platform = platform.inner().clone();
        let clipboard_text = text.clone();
        tauri::async_runtime::spawn_blocking(move || {
            platform
                .copy_text(&clipboard_text)
                .map_err(|_| HostActionError {
                    code: "unavailable",
                })
        })
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })??;
        if clipboard_enabled(&store)? {
            store
                .capture_clipboard_text(text)
                .map_err(|_| HostActionError {
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
        return Ok(());
    }
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    {
        tauri::async_runtime::spawn_blocking(move || copy_text_blocking(text, &state, &store))
            .await
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
    }
}

#[cfg(target_os = "android")]
#[tauri::command]
async fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    account: tauri::State<'_, android_account::AccountState>,
) -> Result<(), HostActionError> {
    copy_text_impl(text, state, store, account).await
}

#[cfg(target_os = "ios")]
#[tauri::command]
async fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
    platform: tauri::State<'_, MobilePlatform<tauri::Wry>>,
) -> Result<(), HostActionError> {
    copy_text_impl(text, state, store, platform).await
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
#[tauri::command]
async fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
    store: tauri::State<'_, std::sync::Arc<PreferencesStore>>,
) -> Result<(), HostActionError> {
    copy_text_impl(text, state, store).await
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
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
        store
            .capture_clipboard_text(text)
            .map_err(|_| HostActionError {
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

#[cfg(any(target_os = "ios", test))]
fn ios_host_options_document(
    contents: Option<&str>,
    resources: &std::path::Path,
    state_root: &std::path::Path,
) -> Result<Value, String> {
    match contents {
        Some(contents) => serde_json::from_str(contents)
            .map_err(|_| "Cannot parse prepared HostOptions JSON".to_owned()),
        None => Ok(serde_json::json!({
            "resources": resources.to_string_lossy(),
            "state_root": state_root.to_string_lossy(),
        })),
    }
}

#[cfg(any(target_os = "ios", test))]
fn ios_custom_skin_library_root(state_root: &std::path::Path) -> PathBuf {
    state_root
        .parent()
        .map(std::path::Path::to_path_buf)
        .unwrap_or_else(|| state_root.to_path_buf())
}

#[cfg(target_os = "ios")]
#[tauri::command]
async fn open_system_keyboard_settings(
    state: tauri::State<'_, msime_tauri_mobile_platform::MobilePlatform<tauri::Wry>>,
) -> Result<(), CommandError> {
    let platform = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || platform.open_system_keyboard_settings())
        .await
        .map_err(|_| CommandError {
            code: "system_settings",
        })?
        .map_err(|_| CommandError {
            code: "system_settings",
        })
}

#[cfg(target_os = "ios")]
#[tauri::command]
async fn app_icon_info(
    state: tauri::State<'_, msime_tauri_mobile_platform::MobilePlatform<tauri::Wry>>,
) -> Result<msime_tauri_mobile_platform::AppIconInfo, CommandError> {
    let platform = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || platform.app_icon_info())
        .await
        .map_err(|_| CommandError { code: "app_icon" })?
        .map_err(|_| CommandError { code: "app_icon" })
}

#[cfg(target_os = "ios")]
#[tauri::command]
async fn app_icon_set(
    state: tauri::State<'_, msime_tauri_mobile_platform::MobilePlatform<tauri::Wry>>,
    style: String,
) -> Result<msime_tauri_mobile_platform::AppIconInfo, CommandError> {
    if !msime_tauri_mobile_platform::is_supported_app_icon_style(&style) {
        return Err(CommandError {
            code: "invalid_app_icon",
        });
    }
    let platform = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || platform.set_app_icon(&style))
        .await
        .map_err(|_| CommandError { code: "app_icon" })?
        .map_err(|_| CommandError { code: "app_icon" })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    #[cfg(target_os = "macos")]
    let mut keyboard_launch_target = macos_keyboard::startup_panel(requested_surface_route())
        .and_then(|_| msime_host_macos::capture_launch_target());
    let context = tauri::generate_context!();
    #[cfg(target_os = "macos")]
    let context = {
        let mut context = context;
        macos_keyboard::prepare_windows(
            &mut context.config_mut().app.windows,
            requested_surface_route(),
        );
        macos_panel_session::prepare_windows(
            &mut context.config_mut().app.windows,
            requested_surface_route(),
        );
        macos_cloud_clipboard::prepare_windows(
            &mut context.config_mut().app.windows,
            requested_surface_route(),
        );
        macos_cloud_dictionary::prepare_windows(
            &mut context.config_mut().app.windows,
            requested_surface_route(),
        );
        context
    };
    let builder = tauri::Builder::default();
    #[cfg(target_os = "macos")]
    let builder = builder.plugin(tauri_nspanel::init());
    #[cfg(any(target_os = "linux", target_os = "windows"))]
    let builder = builder.plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
        if let Some(route) = launch_route_from_args(&args) {
            let callback_app = app.clone();
            let _ = app.run_on_main_thread(move || activate_desktop_surface(&callback_app, route));
        }
    }));
    #[cfg(target_os = "android")]
    let builder = builder.plugin(android_account::init());
    #[cfg(target_os = "ios")]
    let builder = builder.plugin(msime_tauri_mobile_platform::init());
    builder
        .setup(|app| {
            #[cfg(target_os = "ios")]
            ios_account::setup(app.handle())?;
            #[cfg(target_os = "macos")]
            app.manage(macos_panel_session::PanelState::from_environment()?);
            #[cfg(target_os = "macos")]
            app.manage(macos_cloud_clipboard::CloudState::from_environment()?);
            #[cfg(target_os = "macos")]
            app.manage(macos_cloud_dictionary::DictionaryState::from_environment()?);
            #[cfg(target_os = "macos")]
            let macos_launch = {
                let options_override = std::env::var_os("MSIME_CLIENT_HOST_OPTIONS")
                    .or_else(|| std::env::var_os("MSIME_IBUS_OPTIONS"));
                let resources_directory = if options_override.is_none() {
                    Some(app.path().resource_dir()?.join("EngineResources"))
                } else {
                    None
                };
                macos_launch::resolve_with_resources(
                    &app.path().app_data_dir()?,
                    resources_directory.as_deref(),
                    options_override,
                    std::env::var_os("MSIME_CLIENT_STATE_DIR"),
                )?
            };
            #[cfg(target_os = "macos")]
            let directory = macos_launch.preferences_directory.clone();
            #[cfg(target_os = "android")]
            let directory = app.path().app_data_dir()?.join("files/bootstrap/state");
            #[cfg(not(any(target_os = "android", target_os = "macos")))]
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
            #[cfg(target_os = "ios")]
            if directory.file_name() == Some(std::ffi::OsStr::new("MSIME")) {
                if let Some(root) = directory.parent() {
                    let _ = msime_host_api::migrate_apple_clipboard_history(root);
                }
            }
            let mut clipboard =
                ClipboardHistoryStore::open(directory.join("clipboard_history.json"));
            let _ = clipboard.load();
            let preferences = Arc::new(PreferencesStore::new(&directory));
            let keyboard_skin_trials =
                KeyboardSkinTrialStore::new(&directory, Arc::clone(&preferences));
            #[cfg(target_os = "android")]
            let _ = keyboard_skin_trials.restore_pending();
            // The iOS keyboard extension stores named designs in the App Group
            // root, while the Rust preferences live below App Group/MSIME.
            // Point both hosts at the same bounded library file.
            #[cfg(target_os = "ios")]
            let custom_skin_directory = ios_custom_skin_library_root(&directory);
            #[cfg(not(target_os = "ios"))]
            let custom_skin_directory = directory.clone();
            app.manage(CustomSkinLibraryStore::new(custom_skin_directory));
            #[cfg(any(target_os = "android", target_os = "ios"))]
            app.manage(msime_client_core::community_resource_library::CommunityResourceLibraryStore::new(
                app.path().app_data_dir()?.join("files/CommunityLibrary.json"),
            ));
            app.manage(keyboard_skin_trials);
            let typing_statistics = TypingStatisticsStore::new(&directory);
            #[cfg(target_os = "ios")]
            if directory.file_name() == Some(std::ffi::OsStr::new("MSIME")) {
                if let Some(legacy_directory) = directory.parent() {
                    let _ = typing_statistics.migrate_from(legacy_directory);
                }
            }
            app.manage(TypingStatisticsState(typing_statistics));
            app.manage(SkinDirectoryState(directory.join("skins")));
            app.manage(preferences.clone());
            let clipboard_state = ClipboardHistoryState(Arc::new(Mutex::new(clipboard)));
            app.manage(ClipboardHistoryState(Arc::clone(&clipboard_state.0)));
            #[cfg(any(target_os = "linux", target_os = "windows", target_os = "macos"))]
            start_desktop_preferences_monitor(
                app.handle(),
                preferences.clone(),
                Arc::clone(&clipboard_state.0),
            );
            #[cfg(target_os = "linux")]
            start_linux_clipboard_monitor(Arc::clone(&clipboard_state.0), preferences);
            app.manage(PanelInputState::default());
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            {
                let linger = DesktopSettingsLinger::default();
                app.manage(linger.clone());
                // The handler belongs to the window: App has no on_window_event,
                // and the label check this replaces only ever admitted "main".
                if let Some(main) = app.get_webview_window("main") {
                    let window = main.clone();
                    main.on_window_event(move |event| {
                        let tauri::WindowEvent::CloseRequested { api, .. } = event else {
                            return;
                        };
                        if linger.quitting.load(Ordering::Acquire) {
                            return;
                        }
                        api.prevent_close();
                        let generation =
                            linger.generation.fetch_add(1, Ordering::AcqRel) + 1;
                        let _ = window.hide();
                        let app = window.app_handle().clone();
                        let linger = linger.clone();
                        std::thread::spawn(move || {
                            std::thread::sleep(std::time::Duration::from_secs(10 * 60));
                            let timer_app = app.clone();
                            let _ = app.run_on_main_thread(move || {
                                if linger
                                    .generation
                                    .compare_exchange(
                                        generation,
                                        generation + 1,
                                        Ordering::AcqRel,
                                        Ordering::Acquire,
                                    )
                                    .is_ok()
                                {
                                    linger.quitting.store(true, Ordering::Release);
                                    if let Some(window) = timer_app.get_webview_window("main") {
                                        let _ = window.close();
                                    }
                                }
                            });
                        });
                    });
                }
            }
            #[cfg(all(unix, not(target_os = "ios")))]
            app.manage(voice_sessions::VoiceSessions::default());
            // Native packaging/installer supplies this verified HostOptions JSON.
            // Webview input never controls resource or state paths.
            #[cfg(target_os = "android")]
            let host_options_path = app
                .path()
                .app_data_dir()?
                .join("files/runtime-options.json");
            #[cfg(target_os = "ios")]
            let host_options_path = directory.join("runtime-options.json");
            #[cfg(target_os = "macos")]
            let host_options_path = macos_launch.options_path;
            #[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
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
            let host_document: Value = {
                #[cfg(target_os = "android")]
                {
                    match fs::read_to_string(&host_options_path) {
                        Ok(host_options) => serde_json::from_str(&host_options)
                            .map_err(|_| "Cannot parse prepared HostOptions JSON".to_string())?,
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                            // The Tauri shell owns the first-run guide. Before the
                            // native bootstrap publishes HostOptions, keep the
                            // managed states valid while resource-backed commands
                            // correctly fail closed until preparation completes.
                            serde_json::json!({
                                "resources": "",
                                "state_root": app.path().app_data_dir()?.join("files/bootstrap/state"),
                            })
                        }
                        Err(_) => return Err("Cannot read prepared HostOptions JSON".into()),
                    }
                }
                #[cfg(target_os = "ios")]
                {
                    let resources = app.path().resource_dir()?.join("EngineResources");
                    match fs::read_to_string(&host_options_path) {
                        Ok(host_options) => ios_host_options_document(
                            Some(&host_options),
                            &resources,
                            &directory,
                        )?,
                        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                            ios_host_options_document(None, &resources, &directory)?
                        }
                        Err(_) => return Err("Cannot read prepared HostOptions JSON".into()),
                    }
                }
                #[cfg(target_os = "macos")]
                {
                    macos_launch.document
                }
                #[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
                {
                    let host_options = fs::read_to_string(&host_options_path)
                        .map_err(|_| "Cannot read prepared HostOptions JSON".to_string())?;
                    serde_json::from_str(&host_options)
                        .map_err(|_| "Cannot parse prepared HostOptions JSON".to_string())?
                }
            };
            let runtime_path = std::env::var_os("MSIME_IBUS_OPTIONS")
                .map(PathBuf::from)
                .filter(|path| path.is_absolute())
                .or_else(|| Some(host_options_path.clone()));
            app.manage(DictionaryHostOptions {
                #[cfg(any(target_os = "linux", target_os = "android"))]
                path: host_options_path,
                #[cfg(not(any(target_os = "linux", target_os = "android")))]
                document: Arc::new(host_document.clone()),
            });
            app.manage(RuntimeOptionsState {
                path: runtime_path,
                document: Arc::new(Mutex::new(host_document)),
            });
            #[cfg(target_os = "macos")]
            if let Some(surface) = macos_keyboard::startup_panel(requested_surface_route())
                .or_else(|| macos_panel_session::startup_panel(requested_surface_route()))
                .or_else(|| macos_cloud_clipboard::startup_panel(requested_surface_route()))
                .or_else(|| macos_cloud_dictionary::startup_panel(requested_surface_route())) {
                open_panel_window(
                    app.handle(), surface.label, surface.query, surface.title,
                    f64::from(surface.width), f64::from(surface.height), None,
                ).map_err(|_| "Cannot open requested native panel".to_string())?;
            }
            // Both desktop hosts launch this shell with the panel their menu
            // named; the IBus property menu and the Windows tray menu are the
            // same contract, so the routes stay in one place.
            #[cfg(any(target_os = "linux", target_os = "windows"))]
            if let Some(route) = requested_surface_route() {
                // A settings route targets the main window, which is already
                // showing; only panel surfaces need a window opened here.
                if let Some(surface) = route.panel() {
                    let (label, route, title, width, height) = (
                        surface.label,
                        surface.query,
                        surface.title,
                        f64::from(surface.width),
                        f64::from(surface.height),
                    );
                    // The menu process is the panel launcher in this path, so
                    // capture the foreground editor before the new window can
                    // take focus. This is the same handoff used by the
                    // settings-page panel commands.
                    let panel_input = app.state::<PanelInputState>();
                    #[cfg(target_os = "linux")]
                    let position = {
                        let _ = remember_panel_input_target(&panel_input, true);
                        panel_position(&panel_input, width, height)
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
            host_capabilities,
            list_voice_capture_devices,
            capture_voice_pcm,
            supports_font_catalog,
            initial_settings_page,
            list_font_families,
            resolve_font_families,
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
            test_api_credential,
            save_preferences,
            list_clipboard_history,
            clear_clipboard_history,
            remove_clipboard_history,
            set_clipboard_history_pinned,
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
            cloud_clipboard_can_send_text,
            cloud_dictionary_request,
            load_emoji_catalog,
            restart_input_method,
            #[cfg(target_os = "android")]
            android_account::account_status,
            #[cfg(target_os = "android")]
            android_account::android_open_input_method_settings,
            #[cfg(target_os = "android")]
            android_account::android_show_input_method_picker,
            #[cfg(target_os = "android")]
            android_account::android_bootstrap_status,
            #[cfg(target_os = "android")]
            android_account::android_prepare_bootstrap,
            #[cfg(target_os = "android")]
            android_account::ai_models,
            #[cfg(target_os = "android")]
            android_account::ai_test,
            #[cfg(target_os = "android")]
            android_account::account_providers,
            #[cfg(target_os = "android")]
            android_account::account_request_code,
            #[cfg(target_os = "android")]
            android_account::account_login,
            #[cfg(target_os = "android")]
            android_account::account_profile,
            #[cfg(target_os = "android")]
            android_account::account_chat_models,
            #[cfg(target_os = "android")]
            android_account::account_chat,
            #[cfg(target_os = "android")]
            android_account::account_rename,
            #[cfg(target_os = "android")]
            android_account::account_logout,
            #[cfg(target_os = "android")]
            android_account::account_delete,
            #[cfg(target_os = "android")]
            android_account::account_forget,
            #[cfg(target_os = "android")]
            android_account::app_icon_info,
            #[cfg(target_os = "android")]
            android_account::app_icon_set,
            #[cfg(target_os = "android")]
            android_account::mobile_keyboard_feedback_load,
            #[cfg(target_os = "android")]
            android_account::mobile_keyboard_feedback_save,
            #[cfg(target_os = "android")]
            android_account::mobile_keyboard_feedback_preview,
            #[cfg(target_os = "ios")]
            open_system_keyboard_settings,
            #[cfg(target_os = "ios")]
            app_icon_info,
            #[cfg(target_os = "ios")]
            app_icon_set,
            #[cfg(target_os = "ios")]
            ios_account::account_status,
            #[cfg(target_os = "ios")]
            ios_account::account_providers,
            #[cfg(target_os = "ios")]
            ios_account::account_request_code,
            #[cfg(target_os = "ios")]
            ios_account::account_login,
            #[cfg(target_os = "ios")]
            ios_account::account_apple_login,
            #[cfg(target_os = "ios")]
            ios_account::account_profile,
            #[cfg(target_os = "ios")]
            ios_account::account_chat_models,
            #[cfg(target_os = "ios")]
            ios_account::account_chat,
            #[cfg(target_os = "ios")]
            ios_account::ai_models,
            #[cfg(target_os = "ios")]
            ios_account::ai_test,
            #[cfg(target_os = "ios")]
            ios_account::account_rename,
            #[cfg(target_os = "ios")]
            ios_account::account_logout,
            #[cfg(target_os = "ios")]
            ios_account::account_delete,
            #[cfg(target_os = "ios")]
            ios_account::account_forget,
            #[cfg(target_os = "ios")]
            ios_account::account_preferences_schema,
            #[cfg(target_os = "ios")]
            ios_account::account_preferences_load,
            #[cfg(target_os = "ios")]
            ios_account::account_preferences_upload,
            #[cfg(target_os = "ios")]
            ios_account::account_preferences_apply,
            #[cfg(target_os = "ios")]
            ios_account::mobile_keyboard_feedback_load,
            #[cfg(target_os = "ios")]
            ios_account::mobile_keyboard_feedback_save,
            #[cfg(target_os = "ios")]
            ios_account::mobile_keyboard_feedback_preview,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_list,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_detail,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_download,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_rate,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_publish,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_unpublish,
            #[cfg(target_os = "ios")]
            ios_account::community_skin_finish_trial,
            #[cfg(target_os = "ios")]
            ios_account::ai_skin_generate,
            #[cfg(target_os = "ios")]
            ios_account::ai_skin_cancel,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_list,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_detail,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_publish,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_apply,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_save,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_rate,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_unpublish,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_store_reply,
            #[cfg(target_os = "ios")]
            ios_account::community_resource_remove_reply,
            #[cfg(target_os = "android")]
            android_account::account_preferences_schema,
            #[cfg(target_os = "android")]
            android_account::account_preferences_load,
            #[cfg(target_os = "android")]
            android_account::account_preferences_upload,
            #[cfg(target_os = "android")]
            android_account::account_preferences_apply,
            #[cfg(target_os = "android")]
            android_account::community_skin_list,
            #[cfg(target_os = "android")]
            android_account::community_skin_detail,
            #[cfg(target_os = "android")]
            android_account::community_skin_download,
            #[cfg(target_os = "android")]
            android_account::community_skin_rate,
            #[cfg(target_os = "android")]
            android_account::community_skin_publish,
            #[cfg(target_os = "android")]
            android_account::community_skin_unpublish,
            #[cfg(target_os = "android")]
            android_account::community_skin_finish_trial,
            #[cfg(target_os = "android")]
            android_account::ai_skin_generate,
            #[cfg(target_os = "android")]
            android_account::ai_skin_cancel,
            #[cfg(target_os = "android")]
            android_account::community_resource_list,
            #[cfg(target_os = "android")]
            android_account::community_resource_detail,
            #[cfg(target_os = "android")]
            android_account::community_resource_publish,
            #[cfg(target_os = "android")]
            android_account::community_resource_apply,
            #[cfg(target_os = "android")]
            android_account::community_resource_save,
            #[cfg(target_os = "android")]
            android_account::community_resource_rate,
            #[cfg(target_os = "android")]
            android_account::community_resource_unpublish,
            #[cfg(target_os = "android")]
            android_account::community_resource_store_reply,
            #[cfg(target_os = "android")]
            android_account::community_resource_remove_reply,
        ])
        .build(context)
        .expect("client application failed")
        .run(move |_app, _event| {
            #[cfg(target_os = "macos")]
            if matches!(_event, tauri::RunEvent::Ready) {
                if let Some(target) = keyboard_launch_target.take() {
                    let _ = msime_host_macos::restore_launch_target(target);
                }
            }
            #[cfg(target_os = "macos")]
            if matches!(_event, tauri::RunEvent::WindowEvent { event: tauri::WindowEvent::Destroyed, .. })
                && (macos_keyboard::startup_panel(requested_surface_route()).is_some()
                    || macos_panel_session::startup_panel(requested_surface_route()).is_some()
                    || macos_cloud_clipboard::startup_panel(requested_surface_route()).is_some()
                    || macos_cloud_dictionary::startup_panel(requested_surface_route()).is_some())
                && !_app.webview_windows().values().any(|window| window.is_visible().unwrap_or(true))
            {
                // A panel-only launcher does not leave an invisible settings
                // process behind. Other visible panels keep the process alive.
                _app.exit(0);
            }
        });
}

#[cfg(all(test, any(target_os = "macos", target_os = "windows")))]
mod credential_command_tests;

#[cfg(test)]
mod tests {
    #[test]
    fn windows_restart_payload_is_exact_utf16_without_terminator() {
        let payload = super::windows_restart_payload();
        let expected: Vec<u8> = "RestartServer"
            .encode_utf16()
            .flat_map(|unit| unit.to_le_bytes())
            .collect();
        assert_eq!(payload, expected);
        assert_eq!(payload.len(), "RestartServer".encode_utf16().count() * 2);
    }

    #[test]
    fn external_links_require_clean_https_urls() {
        for url in [
            "https://example.com/help",
            "https://updates.example.com/v1?channel=stable",
        ] {
            assert!(super::external_url_is_safe(url));
        }
        for url in [
            "https://",
            "https:///path",
            "http://example.com",
            "https://example.com/help path",
            "https://example.com/a&b",
            "https://example.com/\"quoted\"",
            "https://example.com/\\escape",
        ] {
            assert!(!super::external_url_is_safe(url));
        }
    }

    #[test]
    fn ios_clipboard_history_is_permission_gated_not_preference_gated() {
        assert!(!super::clipboard_history_uses_preference(
            msime_client_core::host_surface::HostPlatform::Ios
        ));
        for platform in [
            msime_client_core::host_surface::HostPlatform::Windows,
            msime_client_core::host_surface::HostPlatform::Macos,
            msime_client_core::host_surface::HostPlatform::Linux,
            msime_client_core::host_surface::HostPlatform::Android,
        ] {
            assert!(super::clipboard_history_uses_preference(platform));
        }
    }

    #[test]
    fn ios_routes_only_app_group_dictionary_operations() {
        for operation in [
            "list",
            "edit",
            "import_personal",
            "export",
            "retry",
            "dismiss_failure",
        ] {
            assert!(super::ios_personal_dictionary_action(
                &serde_json::json!({ "operation": operation })
            ));
        }
        for action in [
            serde_json::json!({ "operation": "import" }),
            serde_json::json!({ "operation": "unknown" }),
            serde_json::json!({}),
            serde_json::Value::Null,
        ] {
            assert!(!super::ios_personal_dictionary_action(&action));
        }
    }

    #[test]
    fn ios_first_run_host_options_use_packaged_resources_and_shared_state() {
        let document = super::ios_host_options_document(
            None,
            std::path::Path::new("/fixture/resources"),
            std::path::Path::new("/fixture/shared-state"),
        )
        .expect("first-run options");
        assert_eq!(document["resources"], "/fixture/resources");
        assert_eq!(document["state_root"], "/fixture/shared-state");
    }

    #[test]
    fn ios_named_skin_library_shares_the_apple_app_group_root() {
        let root =
            super::ios_custom_skin_library_root(std::path::Path::new("/fixture/app-group/MSIME"));
        assert_eq!(root, std::path::Path::new("/fixture/app-group"));
        assert_eq!(
            msime_client_core::custom_skin_library::CustomSkinLibraryStore::new(root).path(),
            std::path::Path::new("/fixture/app-group/CustomSkins/library.json")
        );
    }

    #[test]
    fn ios_prepared_host_options_are_preserved_and_malformed_json_is_rejected() {
        let prepared = r#"{"resources":"/prepared","state_root":"/state","api_version":1}"#;
        let document = super::ios_host_options_document(
            Some(prepared),
            std::path::Path::new("/unused/resources"),
            std::path::Path::new("/unused/state"),
        )
        .expect("prepared options");
        assert_eq!(document["resources"], "/prepared");
        assert_eq!(document["state_root"], "/state");
        assert!(super::ios_host_options_document(
            Some("{"),
            std::path::Path::new("/unused/resources"),
            std::path::Path::new("/unused/state"),
        )
        .is_err());
    }

    #[test]
    fn ios_voice_batch_configuration_uses_current_preferences_and_safe_defaults() {
        let mut preferences = msime_client_core::preferences::Preferences::default();
        preferences.voice_input.asr_provider = "openai".into();
        preferences.voice_input.asr_endpoint.clear();
        preferences.voice_input.asr_model.clear();
        preferences.voice_input.asr_token = "synthetic-current".into();
        preferences
            .voice_input
            .asr_tokens
            .insert("openai".into(), "synthetic-stale".into());
        let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
        assert_eq!(configuration.provider, "openai");
        assert_eq!(
            configuration.endpoint,
            "https://api.openai.com/v1/audio/transcriptions"
        );
        assert_eq!(configuration.model, "whisper-1");
        assert_eq!(configuration.token, "synthetic-current");
        assert!(configuration.headers.is_empty());

        preferences.voice_input.asr_provider = "groq".into();
        preferences.voice_input.asr_endpoint = "https://fixture.invalid/transcribe".into();
        preferences.voice_input.asr_model = "fixture-model".into();
        preferences.voice_input.asr_token.clear();
        preferences
            .voice_input
            .asr_tokens
            .insert("groq".into(), "synthetic-slot".into());
        let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
        assert_eq!(configuration.endpoint, "https://fixture.invalid/transcribe");
        assert_eq!(configuration.model, "fixture-model");
        assert_eq!(configuration.token, "synthetic-slot");
        assert!(configuration.headers.is_empty());
    }

    #[test]
    fn ios_keyboard_ai_preferences_resolve_origin_tokens_and_disable_incomplete_drafts() {
        let mut preferences = msime_client_core::preferences::Preferences::default();
        preferences.ai_assistant.enabled = true;
        preferences.ai_assistant.provider = "deepseek".into();
        preferences.ai_assistant.endpoint =
            "https://API.Example.invalid/v1/chat/completions".into();
        preferences.ai_assistant.model = "fixture-model".into();
        preferences.ai_assistant.prompt = "只返回结果".into();
        preferences.ai_assistant.tokens.insert(
            "https://api.example.invalid:443".into(),
            "fixture-origin-token".into(),
        );
        let native = super::ios_keyboard_ai_preferences(&preferences.ai_assistant);
        assert!(native.enabled);
        assert_eq!(native.provider, "deepSeek");
        assert_eq!(native.token, "fixture-origin-token");

        preferences.ai_assistant.tokens.clear();
        assert!(!super::ios_keyboard_ai_preferences(&preferences.ai_assistant).enabled);
    }

    #[test]
    fn ios_voice_doubao_configuration_uses_shared_auth_and_current_preferences() {
        let mut preferences = msime_client_core::preferences::Preferences::default();
        preferences.voice_input.asr_token = "synthetic-key".into();
        preferences.voice_input.asr_app_key = "stale-app".into();
        preferences.voice_input.doubao_auth_mode = "api_key".into();
        preferences.voice_input.doubao_boosting_table_id = "fixture-table".into();
        let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
        assert_eq!(configuration.provider, "doubao");
        assert_eq!(
            configuration.endpoint,
            "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
        );
        assert!(configuration.model.is_empty());
        assert!(configuration.token.is_empty());
        assert!(configuration.enable_itn);
        assert!(configuration.enable_punctuation);
        assert!(!configuration.enable_ddc);
        assert_eq!(configuration.boosting_table_id, "fixture-table");
        assert!(configuration
            .headers
            .iter()
            .any(|header| header.name == "x-api-key" && header.value == "synthetic-key"));
        assert!(!configuration
            .headers
            .iter()
            .any(|header| header.name == "x-api-app-key"));

        preferences.voice_input.doubao_auth_mode = "legacy".into();
        preferences.voice_input.asr_app_key = "synthetic-app".into();
        let configuration = super::ios_voice_provider_configuration(&preferences).unwrap();
        assert!(configuration
            .headers
            .iter()
            .any(|header| header.name == "x-api-app-key" && header.value == "synthetic-app"));
        assert!(configuration
            .headers
            .iter()
            .any(|header| header.name == "x-api-access-key"));
    }

    #[test]
    fn macos_voice_devices_match_the_picker_and_exclude_outputs() {
        let document = serde_json::json!({
            "SPAudioDataType": [
                {"_name": "Fixture Speakers", "coreaudio_device_output": 2},
                {"_name": "Fixture Microphone", "coreaudio_device_input": 1,
                 "coreaudio_device_uid": "fixture-input"},
                {"_name": "Fallback Microphone", "coreaudio_device_input": 2},
                {"_name": "Not An Input", "coreaudio_device_input": 0}
            ]
        });

        assert_eq!(
            super::macos_voice_capture_devices(&document),
            vec![
                serde_json::json!({
                    "backend": "macos",
                    "id": "fixture-input",
                    "label": "Fixture Microphone"
                }),
                serde_json::json!({
                    "backend": "macos",
                    "id": "Fallback Microphone",
                    "label": "Fallback Microphone"
                }),
            ]
        );
    }

    #[cfg(unix)]
    #[test]
    fn voice_provider_options_only_forwards_known_doubao_auth_modes() {
        let document = serde_json::json!({
            "preferences": {"voice_input": {
                "doubao_auth_mode": "legacy",
                "asr_app_key": "private-app-id",
                "asr_token": "private-token"
            }}
        });
        let result = super::voice_provider_options(&document);
        assert!(result.is_ok());
        let options = result.ok().expect("voice options should be valid");
        assert_eq!(
            options.get("doubao_auth_mode").and_then(|v| v.as_str()),
            Some("legacy")
        );
        assert!(options.get("asr_app_key").is_none());
        assert!(options.get("asr_token").is_none());

        let document = serde_json::json!({
            "preferences": {"voice_input": {"doubao_auth_mode": "unknown"}}
        });
        let result = super::voice_provider_options(&document);
        assert!(result.is_ok());
        let options = result.ok().expect("voice options should be valid");
        assert!(options.get("doubao_auth_mode").is_none());
    }

    #[cfg(unix)]
    #[test]
    fn voice_provider_options_bound_strings_by_utf8_bytes() {
        let multibyte = "界".repeat(200);
        let document = serde_json::json!({
            "preferences": {"voice_input": {
                "asr_model": multibyte,
                "capture_device": "x".repeat(600)
            }}
        });
        let options = super::voice_provider_options(&document).unwrap();
        let model = options
            .get("asr_model")
            .and_then(|value| value.as_str())
            .unwrap();
        let device = options
            .get("capture_device")
            .and_then(|value| value.as_str())
            .unwrap();

        assert_eq!(model.len(), 510);
        assert_eq!(model.chars().count(), 170);
        assert_eq!(device.len(), 512);
    }

    #[cfg(unix)]
    #[test]
    fn credential_tests_route_to_the_configured_provider_without_credentials() {
        let document = serde_json::json!({
            "online_provider_socket": "/fixture/online.sock",
            "translation_provider_socket": "/fixture/translation.sock",
            "voice_provider_socket": "/fixture/voice.sock",
        });
        assert_eq!(
            super::credential_provider_socket(&document, "ai.assistant"),
            Some(std::path::PathBuf::from("/fixture/online.sock"))
        );
        assert_eq!(
            super::credential_provider_socket(&document, "translation.niutrans"),
            Some(std::path::PathBuf::from("/fixture/translation.sock"))
        );
        assert_eq!(
            super::credential_provider_socket(&document, "voice.polish"),
            Some(std::path::PathBuf::from("/fixture/voice.sock"))
        );
        assert!(super::credential_provider_socket(&document, "unknown").is_none());
    }

    #[test]
    fn second_launch_routes_are_taken_from_explicit_arguments() {
        use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};

        assert_eq!(
            super::launch_route_from_args(&["--route=emoji".into()]),
            Some(SurfaceRoute::Emoji)
        );
        assert_eq!(
            super::launch_route_from_args(&["--route=settings:about".into()])
                .and_then(|route| route.settings_category()),
            Some(SettingsCategory::About)
        );
        assert_eq!(
            super::launch_route_from_args(&["--route=../private".into()]),
            None
        );
        assert_eq!(super::launch_route_from_args(&["--other".into()]), None);
    }

    #[test]
    fn macos_restart_targets_the_input_method_bundle() {
        assert_eq!(
            super::macos_input_source_restart_args(),
            [
                "-n",
                "-b",
                "app.msime.client.preview.inputmethod",
                "--args",
                "--reregister-input-source",
            ]
        );
    }

    #[test]
    fn settings_routes_select_a_page_the_shared_ui_accepts() {
        use msime_client_core::host_surface::{SettingsCategory, SurfaceRoute};
        // The route wins over the compatibility variable, and every category the
        // contract accepts survives the settings-page identifier filter.
        for category in SettingsCategory::ALL {
            let page =
                super::settings_page_from_route(Some(SurfaceRoute::Settings(Some(category))));
            assert_eq!(
                super::requested_settings_page(page.as_deref()),
                Some(category.as_str().to_owned()),
                "category {category:?} is not a usable settings page id"
            );
        }
        assert_eq!(
            super::settings_page_from_route(Some(SurfaceRoute::Settings(None))),
            None
        );
        assert_eq!(
            super::settings_page_from_route(Some(SurfaceRoute::Emoji)),
            None
        );
    }

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
        sync_runtime_options(&state, &preferences).unwrap();
        let updated: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!(updated["preferences"]["candidate_page_size"], 9);
    }
}

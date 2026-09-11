mod update_body;

use msime_client_core::clipboard::ClipboardHistoryStore;
use msime_client_core::cloud::{build_google_url, parse_google_response};
use msime_client_core::preferences::{
    Preferences, PreferencesError, PreferencesSnapshot, PreferencesStore,
};
use msime_client_core::skin_catalog;
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;
use tauri::Manager;

struct DictionaryHostOptions(Arc<String>);
struct DiagnosticState(std::sync::Mutex<(bool, bool)>);
struct ClipboardHistoryState {
    store: std::sync::Mutex<ClipboardHistoryStore>,
    enabled: std::sync::Mutex<bool>,
}
struct SkinState(std::sync::Mutex<Option<String>>);

#[derive(Debug, serde::Serialize)]
struct ExternalSkinSummary {
    id: String,
    name: String,
    version: Option<String>,
    author: Option<String>,
    description: Option<String>,
    compatible: bool,
    issues: Vec<String>,
}

#[derive(Debug, serde::Deserialize, Default)]
#[serde(default)]
struct SkinManifest {
    schema_version: u32,
    id: Option<String>,
    name: Option<String>,
    version: Option<String>,
    author: Option<String>,
    description: Option<String>,
    base: Option<String>,
    toolbar_stylesheet: Option<String>,
    preview: Option<String>,
    supports: SkinSupports,
    candidate_window: Option<SkinWindow>,
}

#[derive(Debug, serde::Deserialize, Default)]
#[serde(default)]
struct SkinSupports {
    layouts: Vec<String>,
    themes: Vec<String>,
}

#[derive(Debug, serde::Deserialize, Default)]
#[serde(default)]
struct SkinWindow {
    min_width_dip: Option<f64>,
    decoration: Option<SkinDecoration>,
}

#[derive(Debug, serde::Deserialize, Default)]
#[serde(default)]
struct SkinDecoration {
    top_inset_dip: Option<f64>,
    width_dip: Option<f64>,
}

fn valid_resource(value: &str, max: usize) -> bool {
    !value.is_empty()
        && value.len() <= max
        && !value.starts_with('/')
        && !value.starts_with('\\')
        && !value.contains('\\')
        && value.split('/').all(|part| {
            !part.is_empty()
                && part != "."
                && part != ".."
                && part
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
        })
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
        run_external_command("open", &[&value])
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
    let shared_catalog = msime_client_core::skin_catalog::scan(&path);
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
        let shared_valid = shared_catalog
            .packages
            .iter()
            .any(|package| package.id == id);
        let manifest = entry.path().join("skin.toml");
        if !manifest.is_file() {
            result.push(ExternalSkinSummary {
                id: id.clone(),
                name: id,
                version: None,
                author: None,
                description: None,
                compatible: false,
                issues: vec!["缺少 skin.toml".into()],
            });
            continue;
        }
        let text = match std::fs::read_to_string(manifest) {
            Ok(text) => text,
            Err(_) => {
                result.push(ExternalSkinSummary {
                    id: id.clone(),
                    name: id,
                    version: None,
                    author: None,
                    description: None,
                    compatible: false,
                    issues: vec!["无法读取 skin.toml".into()],
                });
                continue;
            }
        };
        if text.len() > 256 * 1024 {
            result.push(ExternalSkinSummary {
                id: id.clone(),
                name: id,
                version: None,
                author: None,
                description: None,
                compatible: false,
                issues: vec!["skin.toml 过大".into()],
            });
            continue;
        }
        let manifest: SkinManifest = match toml::from_str(&text) {
            Ok(manifest) => manifest,
            Err(_) => {
                result.push(ExternalSkinSummary {
                    id: id.clone(),
                    name: id,
                    version: None,
                    author: None,
                    description: None,
                    compatible: false,
                    issues: vec!["skin.toml 格式无效".into()],
                });
                continue;
            }
        };
        let mut issues = Vec::new();
        let basic = manifest.schema_version == 1
            && manifest.id.as_deref() == Some(id.as_str())
            && manifest
                .name
                .as_deref()
                .is_some_and(|v| !v.is_empty() && v.len() <= 80)
            && manifest
                .version
                .as_deref()
                .is_some_and(|v| !v.is_empty() && v.len() <= 32)
            && matches!(
                manifest.base.as_deref(),
                Some("fluent" | "wechat" | "graphite" | "willow_green")
            );
        let supports = !manifest.supports.layouts.is_empty()
            && !manifest.supports.themes.is_empty()
            && manifest
                .supports
                .layouts
                .iter()
                .all(|v| matches!(v.as_str(), "horizontal" | "vertical"))
            && manifest
                .supports
                .themes
                .iter()
                .all(|v| matches!(v.as_str(), "dark" | "light"));
        let window = manifest.candidate_window.as_ref().is_some_and(|w| {
            w.min_width_dip.unwrap_or(0.0).is_finite()
                && (0.0..=1000.0).contains(&w.min_width_dip.unwrap_or(0.0))
                && w.decoration.as_ref().is_some_and(|d| {
                    let top = d.top_inset_dip.unwrap_or(0.0);
                    let width = d.width_dip.unwrap_or(0.0);
                    top.is_finite()
                        && width.is_finite()
                        && (0.0..=500.0).contains(&top)
                        && (0.0..=1000.0).contains(&width)
                        && ((top == 0.0) == (width == 0.0))
                })
        });
        let resources = manifest.toolbar_stylesheet.as_deref().is_none_or(|v| {
            valid_resource(v, 128) && v.ends_with(".css") && entry.path().join(v).is_file()
        }) && manifest
            .preview
            .as_deref()
            .is_none_or(|v| valid_resource(v, 256));
        let compatible = shared_valid && basic && supports && window && resources;
        if !compatible {
            issues.push("manifest 不符合 schema_version 1 或缺少有效候选窗配置".into());
        }
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
            issues,
        });
    }
    result.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(result)
}

#[tauri::command]
fn select_skin(
    app: tauri::AppHandle,
    state: tauri::State<'_, SkinState>,
    id: String,
) -> Result<(), HostActionError> {
    if id == "."
        || id == ".."
        || id.is_empty()
        || id.len() > 128
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
    {
        return Err(HostActionError {
            code: "invalid_skin",
        });
    }
    if !matches!(
        id.as_str(),
        "fluent" | "wechat" | "graphite" | "willow_green"
    ) {
        let skin_dir = skin_directory(&app)?;
        if !skin_catalog::scan(&skin_dir)
            .packages
            .iter()
            .any(|package| package.id == id)
        {
            return Err(HostActionError {
                code: "unknown_skin",
            });
        }
    }
    let path = app
        .path()
        .app_data_dir()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .join("selected-skin");
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    }
    let temporary = path.with_extension(format!("tmp-{}", std::process::id()));
    std::fs::write(&temporary, &id).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    if std::fs::rename(&temporary, &path).is_err() {
        let _ = std::fs::remove_file(&temporary);
        return Err(HostActionError {
            code: "unavailable",
        });
    }
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
        Ok(id) => {
            let id = id.trim();
            let valid = !id.is_empty()
                && id.len() <= 128
                && id != "."
                && id != ".."
                && id
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'));
            let builtin = matches!(id, "fluent" | "wechat" | "graphite" | "willow_green");
            let external = skin_directory(&app)?.join(id).is_dir();
            if valid && (builtin || external) {
                Ok(Some(id.to_owned()))
            } else {
                Ok(None)
            }
        }
        Err(_) => Ok(None),
    }
}

#[derive(Debug, serde::Serialize)]
struct HostActionError {
    code: &'static str,
}

#[derive(Debug, serde::Serialize)]
struct UpdateSummary {
    found: bool,
    version: Option<String>,
    installer_name: Option<String>,
    installer_sha256: Option<String>,
    signed: Option<bool>,
}

#[tauri::command]
fn clear_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<(), HostActionError> {
    state
        .store
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
fn list_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<Vec<String>, HostActionError> {
    let history = state.store.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    Ok(history.entries().to_vec())
}

#[tauri::command]
fn sync_clipboard_history(
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<Vec<String>, HostActionError> {
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
    let text = String::from_utf8(output.stdout).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    if !*state.enabled.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })? {
        return Ok(Vec::new());
    }
    let mut history = state.store.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    history
        .push(text.trim_end_matches(['\r', '\n']).to_owned())
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    Ok(history.entries().to_vec())
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

#[tauri::command]
fn get_diagnostic_log(
    state: tauri::State<'_, DiagnosticState>,
    scope: String,
) -> Result<bool, HostActionError> {
    let values = state.0.lock().map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    match scope.as_str() {
        "server" => Ok(values.0),
        "tsf" => Ok(values.1),
        _ => Err(HostActionError {
            code: "invalid_scope",
        }),
    }
}

fn run_external_command(program: &str, args: &[&str]) -> Result<(), HostActionError> {
    let status = std::process::Command::new(program)
        .args(args)
        .status()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    if status.success() {
        Ok(())
    } else {
        Err(HostActionError {
            code: "unavailable",
        })
    }
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
        run_external_command("open", &[&url])
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
    allowed.iter().any(|prefix| {
        url == *prefix
            || url
                .strip_prefix(prefix)
                .is_some_and(|rest| rest.starts_with('/'))
    }) && !url.chars().any(|character| {
        character.is_whitespace()
            || character.is_control()
            || matches!(character, '&' | '|' | '<' | '>' | '^' | '%')
    })
}

#[cfg(test)]
mod tests {
    use super::validate_update_metadata;
    use super::{compare_versions, is_allowed_external_url, is_valid_version};

    #[test]
    fn compares_release_versions_without_padding_bugs() {
        assert_eq!(
            compare_versions("v1.2.0", "1.1.9"),
            std::cmp::Ordering::Greater
        );
        assert_eq!(compare_versions("1.2", "1.2.0"), std::cmp::Ordering::Equal);
        assert_eq!(compare_versions("0.9", "1.0"), std::cmp::Ordering::Less);
    }

    #[test]
    fn rejects_malformed_release_versions() {
        assert!(is_valid_version("v1.2.3"));
        assert!(!is_valid_version("latest"));
        assert!(!is_valid_version("1..2"));
    }

    #[test]
    fn external_url_allowlist_rejects_shell_metacharacters() {
        assert!(is_allowed_external_url(
            "https://github.com/metasequoiaime/MSIME-Client/releases"
        ));
        assert!(is_allowed_external_url("https://t.me/msimegroup"));
        assert!(!is_allowed_external_url("https://example.com"));
        assert!(!is_allowed_external_url(
            "https://github.com/metasequoiaime/MSIME-Client.evil.example/releases"
        ));
        assert!(!is_allowed_external_url(
            "https://github.com/metasequoiaime/MSIME-Client&bad"
        ));
    }

    #[test]
    fn update_metadata_accepts_release_pipeline_shape() {
        let value = serde_json::json!({
            "installerName": "MetasequoiaIME_Setup_v1.2.3.exe",
            "installerSha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            "signed": true
        });
        assert!(validate_update_metadata(&value).is_ok());
    }

    #[test]
    fn update_metadata_rejects_tampered_optional_fields() {
        for (key, value) in [
            ("installerName", serde_json::json!("setup.exe")),
            ("installerSha256", serde_json::json!("not-a-digest")),
            ("signed", serde_json::json!("yes")),
        ] {
            let value = serde_json::json!({ key: value });
            assert!(validate_update_metadata(&value).is_err(), "{key}");
        }
    }
}

fn check_for_updates_blocking() -> Result<UpdateSummary, HostActionError> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .user_agent(concat!("MSIME-Client/", env!("CARGO_PKG_VERSION")))
        .build()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    let response = client
        .get("https://msime.app/update.json")
        .send()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
        .error_for_status()
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("");
    if !content_type
        .to_ascii_lowercase()
        .starts_with("application/json")
    {
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    let manifest = update_body::read_manifest(response).map_err(|_| HostActionError {
        code: "unavailable",
    })?;
    let manifest: serde_json::Value =
        serde_json::from_slice(&manifest).map_err(|_| HostActionError {
            code: "unavailable",
        })?;
    let version = manifest
        .get("version")
        .and_then(serde_json::Value::as_str)
        .ok_or(HostActionError {
            code: "unavailable",
        })?;
    if !is_valid_version(version) {
        return Err(HostActionError {
            code: "unavailable",
        });
    }
    validate_update_metadata(&manifest)?;
    if compare_versions(version, env!("CARGO_PKG_VERSION")) == std::cmp::Ordering::Greater {
        let url = manifest
            .get("releaseUrl")
            .and_then(serde_json::Value::as_str)
            .ok_or(HostActionError {
                code: "unavailable",
            })?;
        if !is_allowed_external_url(url) {
            return Err(HostActionError {
                code: "invalid_url",
            });
        }
        open_external_url(url.to_owned())?;
        return Ok(UpdateSummary {
            found: true,
            version: Some(version.to_owned()),
            installer_name: manifest
                .get("installerName")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned),
            installer_sha256: manifest
                .get("installerSha256")
                .and_then(serde_json::Value::as_str)
                .map(str::to_owned),
            signed: manifest.get("signed").and_then(serde_json::Value::as_bool),
        });
    }
    Ok(UpdateSummary {
        found: false,
        version: None,
        installer_name: None,
        installer_sha256: None,
        signed: None,
    })
}

fn validate_update_metadata(manifest: &serde_json::Value) -> Result<(), HostActionError> {
    if let Some(name) = manifest.get("installerName") {
        let valid = name.as_str().is_some_and(|value| {
            value.len() <= 128
                && value.starts_with("MetasequoiaIME_Setup_v")
                && value.ends_with(".exe")
                && value
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
        });
        if !valid {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
    }
    if let Some(digest) = manifest.get("installerSha256") {
        let valid = digest.as_str().is_some_and(|value| {
            value.len() == 64 && value.bytes().all(|byte| byte.is_ascii_hexdigit())
        });
        if !valid {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
    }
    if let Some(signed) = manifest.get("signed") {
        if !signed.is_boolean() {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
    }
    Ok(())
}

#[tauri::command]
async fn check_for_updates() -> Result<UpdateSummary, HostActionError> {
    tauri::async_runtime::spawn_blocking(check_for_updates_blocking)
        .await
        .map_err(|_| HostActionError {
            code: "unavailable",
        })?
}

fn compare_versions(left: &str, right: &str) -> std::cmp::Ordering {
    let parse = |value: &str| {
        value
            .trim_start_matches('v')
            .split('.')
            .map(|part| part.parse::<u64>().unwrap_or(0))
            .collect::<Vec<_>>()
    };
    let (left, right) = (parse(left), parse(right));
    (0..left.len().max(right.len()))
        .map(|index| {
            (
                left.get(index).copied().unwrap_or(0),
                right.get(index).copied().unwrap_or(0),
            )
        })
        .find_map(|(left, right)| (left != right).then_some(left.cmp(&right)))
        .unwrap_or(std::cmp::Ordering::Equal)
}

fn is_valid_version(value: &str) -> bool {
    let value = value.strip_prefix('v').unwrap_or(value);
    !value.is_empty()
        && value
            .split('.')
            .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit()))
}

#[tauri::command]
fn open_screen_keyboard() -> Result<(), HostActionError> {
    #[cfg(target_os = "linux")]
    {
        return run_external_command("onboard", &[]);
    }
    #[cfg(target_os = "macos")]
    {
        run_external_command("open", &["/System/Library/CoreServices/KeyboardViewer.app"])
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
fn open_handwriting() -> Result<(), HostActionError> {
    #[cfg(target_os = "windows")]
    {
        // The Windows touch keyboard hosts the handwriting panel; launching it keeps
        // the action independent from the TSF process boundary.
        return run_external_command("tabtip.exe", &[]);
    }
    #[cfg(target_os = "linux")]
    {
        return run_external_command("onboard", &["--layout", "Handwriting"]);
    }
    #[cfg(target_os = "macos")]
    {
        run_external_command("open", &["/System/Library/CoreServices/KeyboardViewer.app"])
    }
    #[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
    {
        Err(HostActionError {
            code: "unavailable",
        })
    }
}

#[tauri::command]
fn copy_text(
    text: String,
    state: tauri::State<'_, ClipboardHistoryState>,
) -> Result<(), HostActionError> {
    let record = || {
        state
            .store
            .lock()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .push(text.clone())
            .map(|_| ())
            .map_err(|_| HostActionError {
                code: "unavailable",
            })
    };
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
        if !child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
        {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        record()
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
        if !child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
        {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        return record();
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
        if !child
            .wait()
            .map_err(|_| HostActionError {
                code: "unavailable",
            })?
            .success()
        {
            return Err(HostActionError {
                code: "unavailable",
            });
        }
        return record();
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

#[tauri::command]
async fn fetch_cloud_candidate(
    input: String,
    japanese: bool,
) -> Result<Option<String>, CommandError> {
    tauri::async_runtime::spawn_blocking(move || {
        let url = build_google_url(&input, japanese).ok_or(CommandError {
            code: "invalid_input",
        })?;
        let response = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(2))
            .user_agent(concat!("MSIME-Client/", env!("CARGO_PKG_VERSION")))
            .build()
            .map_err(|_| CommandError {
                code: "unavailable",
            })?
            .get(url)
            .send()
            .map_err(|_| CommandError {
                code: "unavailable",
            })?
            .error_for_status()
            .map_err(|_| CommandError {
                code: "unavailable",
            })?;
        if response
            .content_length()
            .is_some_and(|length| length > 256 * 1024)
        {
            return Err(CommandError {
                code: "unavailable",
            });
        }
        let bytes = response.bytes().map_err(|_| CommandError {
            code: "unavailable",
        })?;
        if bytes.len() > 256 * 1024 {
            return Err(CommandError {
                code: "unavailable",
            });
        }
        Ok(parse_google_response(&bytes))
    })
    .await
    .map_err(|_| CommandError {
        code: "unavailable",
    })?
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
    clipboard: tauri::State<'_, ClipboardHistoryState>,
    expected_revision: u64,
    preferences: Preferences,
) -> Result<PreferencesSnapshot, CommandError> {
    let store = store.inner().clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        store
            .save(expected_revision, preferences)
            .map_err(CommandError::from)
    })
    .await
    .map_err(|_| CommandError { code: "storage" })??;
    *clipboard
        .enabled
        .lock()
        .map_err(|_| CommandError { code: "storage" })? = result.preferences.clipboard_history;
    Ok(result)
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
            let preferences_store = PreferencesStore::new(&directory);
            let clipboard_enabled = preferences_store
                .load()
                .map(|snapshot| snapshot.preferences.clipboard_history)
                .unwrap_or(true);
            app.manage(std::sync::Arc::new(preferences_store));
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
            let mut clipboard =
                ClipboardHistoryStore::open(directory.join("clipboard_history.json"));
            let _ = clipboard.load();
            app.manage(ClipboardHistoryState {
                store: std::sync::Mutex::new(clipboard),
                enabled: std::sync::Mutex::new(clipboard_enabled),
            });
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
            open_handwriting,
            copy_text,
            open_skin_directory,
            refresh_skin_catalog,
            list_external_skins,
            set_diagnostic_log,
            get_diagnostic_log,
            clear_clipboard_history,
            list_clipboard_history,
            sync_clipboard_history,
            select_skin,
            selected_skin,
            fetch_cloud_candidate
        ])
        .run(tauri::generate_context!())
        .expect("client application failed");
}

//! Linux online provider credential files.
//!
//! Windows and macOS keep AI tokens and translation secrets in the shared preferences document, because the shell itself sends those requests. On Linux the network requests belong to the user's `msime-client-online-provider` service, which reads `ai-provider.json` and `tencent-provider.json` from `$XDG_CONFIG_HOME/msime-client` on every request. This module lets the settings page write those two files instead of asking the user to hand-edit JSON: the provider picks the change up on the next request, without a restart.
//!
//! The files follow the provider's own reader (`load_private_config`, `load_ai_config`, `load_tencent_config`): a regular file owned by this user with no group or other bits, at most 16 KiB, published by rename so the provider never reads a half-written document. Validation mirrors the provider's, so a document this module writes is one the provider accepts - the AI file is validated as a whole, and a single bad profile would disable every provider in it.
//!
//! The React surface only learns which providers have a credential and the endpoint and model each one is bound to. Secrets travel from the webview into this process and never back.

use reqwest::Url;
use serde::Serialize;
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::Mutex;

/// The provider's `load_private_config` reads at most this many bytes.
const MAX_PROVIDER_CONFIG_BYTES: usize = 16 * 1024;
/// The provider's `load_ai_config` rejects more profiles than this.
const MAX_AI_PROFILES: usize = 16;
const AI_FILE: &str = "ai-provider.json";
const TENCENT_FILE: &str = "tencent-provider.json";

/// Serialises read-modify-write of the two files within this process.
static WRITE_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum CredentialError {
    /// No usable `$XDG_CONFIG_HOME` or `$HOME`.
    Location,
    /// The existing file is not one this host or the provider would accept: wrong owner or mode, a symlink, too large, or not the expected JSON.
    Existing,
    Storage,
    InvalidProvider,
    InvalidEndpoint,
    InvalidModel,
    InvalidToken,
    TokenRequired,
    TooManyProfiles,
    InvalidSecret,
    InvalidRegion,
}

impl CredentialError {
    fn code(&self) -> &'static str {
        match self {
            Self::Location => "provider_credentials_location",
            Self::Existing => "provider_credentials_existing_invalid",
            Self::Storage => "provider_credentials_storage",
            Self::InvalidProvider => "provider_credentials_invalid_provider",
            Self::InvalidEndpoint => "provider_credentials_invalid_endpoint",
            Self::InvalidModel => "provider_credentials_invalid_model",
            Self::InvalidToken => "provider_credentials_invalid_token",
            Self::TokenRequired => "provider_credentials_token_required",
            Self::TooManyProfiles => "provider_credentials_too_many_profiles",
            Self::InvalidSecret => "provider_credentials_invalid_secret",
            Self::InvalidRegion => "provider_credentials_invalid_region",
        }
    }
}

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AiCredentialStatus {
    provider: String,
    endpoint: String,
    model: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TencentCredentialStatus {
    region: String,
}

#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderCredentialStatus {
    ai: Vec<AiCredentialStatus>,
    /// The AI file exists but the provider would refuse it, so no AI provider works until it is saved again or removed.
    ai_invalid: bool,
    tencent: Option<TencentCredentialStatus>,
    tencent_invalid: bool,
}

/// `$XDG_CONFIG_HOME/msime-client`, resolved the way `msime-client-provider-session` resolves it: a relative `XDG_CONFIG_HOME` is an error, not a fallback.
fn config_directory() -> Result<PathBuf, CredentialError> {
    let base = match std::env::var_os("XDG_CONFIG_HOME").filter(|value| !value.is_empty()) {
        Some(value) => PathBuf::from(value),
        None => PathBuf::from(
            std::env::var_os("HOME")
                .filter(|value| !value.is_empty())
                .ok_or(CredentialError::Location)?,
        )
        .join(".config"),
    };
    if !base.is_absolute() {
        return Err(CredentialError::Location);
    }
    Ok(base.join("msime-client"))
}

/// The document at `path`, `None` when there is none. A file the provider's reader would refuse is an error rather than something to overwrite: the user may have put it there by hand.
fn read_private(path: &Path) -> Result<Option<Map<String, Value>>, CredentialError> {
    let metadata = match std::fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(CredentialError::Storage),
    };
    if !metadata.is_file()
        || metadata.uid() != rustix::process::geteuid().as_raw()
        || metadata.mode() & 0o077 != 0
        || metadata.len() > MAX_PROVIDER_CONFIG_BYTES as u64
    {
        return Err(CredentialError::Existing);
    }
    let text = std::fs::read_to_string(path).map_err(|_| CredentialError::Storage)?;
    match serde_json::from_str::<Value>(&text) {
        Ok(Value::Object(map)) => Ok(Some(map)),
        _ => Err(CredentialError::Existing),
    }
}

/// Publish `document` at `path` owner-only, or remove the file when there is nothing left to store.
fn write_private(path: &Path, document: Option<&Value>) -> Result<(), CredentialError> {
    let Some(document) = document else {
        return match std::fs::remove_file(path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(_) => Err(CredentialError::Storage),
        };
    };
    let mut value = serde_json::to_vec_pretty(document).map_err(|_| CredentialError::Storage)?;
    value.push(b'\n');
    if value.len() > MAX_PROVIDER_CONFIG_BYTES {
        return Err(CredentialError::TooManyProfiles);
    }
    let directory = path.parent().ok_or(CredentialError::Storage)?;
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(directory)
        .map_err(|_| CredentialError::Storage)?;
    // Created 0600 from the start: between a create and a chmod the secret would be readable.
    let temporary = path.with_extension("json.new");
    let _ = std::fs::remove_file(&temporary);
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&temporary)
        .map_err(|_| CredentialError::Storage)?;
    let written = file
        .write_all(&value)
        .and_then(|()| file.sync_all())
        .map_err(|_| CredentialError::Storage);
    drop(file);
    if let Err(error) = written {
        let _ = std::fs::remove_file(&temporary);
        return Err(error);
    }
    if std::fs::rename(&temporary, path).is_err() {
        let _ = std::fs::remove_file(&temporary);
        return Err(CredentialError::Storage);
    }
    Ok(())
}

/// Surrounding whitespace the provider strips before it validates.
fn trim_pasted(value: &str) -> &str {
    value.trim_matches([' ', '\t', '\r', '\n'])
}

fn has_control(value: &str) -> bool {
    value
        .chars()
        .any(|character| (character as u32) < 32 || (127..=159).contains(&(character as u32)))
}

/// A secret as the provider accepts it: printable ASCII, and not an obvious placeholder.
fn valid_secret(value: &str) -> bool {
    !value.is_empty()
        && value.bytes().all(|byte| (33..=126).contains(&byte))
        && !value.starts_with('<')
        && !value.starts_with("FAKESECRET_")
}

fn valid_endpoint(value: &str) -> bool {
    Url::parse(value).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str().is_some_and(|host| !host.is_empty())
            && url.username().is_empty()
            && url.password().is_none()
            && url.fragment().is_none()
    })
}

type AiEntries = BTreeMap<String, Map<String, Value>>;

/// Every AI entry in the document keyed by provider, whether it sits at the top level or under `profiles`. Extra keys in an entry are kept so a hand-written field survives a save.
fn ai_entries(document: &Map<String, Value>) -> Result<AiEntries, CredentialError> {
    let mut entries = AiEntries::new();
    if document.contains_key("provider") {
        let provider = document
            .get("provider")
            .and_then(Value::as_str)
            .ok_or(CredentialError::Existing)?;
        let mut entry = document.clone();
        entry.remove("profiles");
        entries.insert(provider.to_owned(), entry);
    }
    match document.get("profiles") {
        None => {}
        Some(Value::Object(profiles)) => {
            for (provider, entry) in profiles {
                let Value::Object(entry) = entry else {
                    return Err(CredentialError::Existing);
                };
                if entries.contains_key(provider) {
                    return Err(CredentialError::Existing);
                }
                let mut entry = entry.clone();
                entry.insert("provider".into(), Value::String(provider.clone()));
                entries.insert(provider.clone(), entry);
            }
        }
        Some(_) => return Err(CredentialError::Existing),
    }
    Ok(entries)
}

fn entry_text<'a>(entry: &'a Map<String, Value>, key: &str) -> &'a str {
    entry.get(key).and_then(Value::as_str).unwrap_or_default()
}

/// The checks `load_ai_config` applies to each entry.
fn validate_ai_entry(entry: &Map<String, Value>) -> Result<(), CredentialError> {
    let provider = trim_pasted(entry_text(entry, "provider"));
    if provider.is_empty() || provider.chars().count() > 64 || has_control(provider) {
        return Err(CredentialError::InvalidProvider);
    }
    let endpoint = trim_pasted(entry_text(entry, "endpoint"));
    if has_control(endpoint) || !valid_endpoint(endpoint) {
        return Err(CredentialError::InvalidEndpoint);
    }
    let model = trim_pasted(entry_text(entry, "model"));
    if model.is_empty() || has_control(model) {
        return Err(CredentialError::InvalidModel);
    }
    if !valid_secret(trim_pasted(entry_text(entry, "token"))) {
        return Err(CredentialError::InvalidToken);
    }
    Ok(())
}

/// Written as `{"profiles": {...}}`: one shape for any number of providers, which `load_ai_config` reads the same as a top-level entry.
fn ai_document(entries: AiEntries) -> Result<Option<Value>, CredentialError> {
    if entries.is_empty() {
        return Ok(None);
    }
    if entries.len() > MAX_AI_PROFILES {
        return Err(CredentialError::TooManyProfiles);
    }
    let mut profiles = Map::new();
    for (provider, mut entry) in entries {
        validate_ai_entry(&entry)?;
        entry.remove("provider");
        profiles.insert(provider, Value::Object(entry));
    }
    let mut document = Map::new();
    document.insert("profiles".into(), Value::Object(profiles));
    Ok(Some(Value::Object(document)))
}

fn ai_status(document: &Map<String, Value>) -> Result<Vec<AiCredentialStatus>, CredentialError> {
    let entries = ai_entries(document)?;
    if entries.len() > MAX_AI_PROFILES {
        return Err(CredentialError::Existing);
    }
    let mut status = Vec::new();
    for (provider, entry) in &entries {
        validate_ai_entry(entry).map_err(|_| CredentialError::Existing)?;
        status.push(AiCredentialStatus {
            provider: provider.clone(),
            endpoint: trim_pasted(entry_text(entry, "endpoint")).to_owned(),
            model: trim_pasted(entry_text(entry, "model")).to_owned(),
        });
    }
    Ok(status)
}

fn tencent_status(
    document: &Map<String, Value>,
) -> Result<TencentCredentialStatus, CredentialError> {
    for key in ["secret_id", "secret_key"] {
        if !valid_secret(trim_pasted(entry_text(document, key))) {
            return Err(CredentialError::Existing);
        }
    }
    let region = match document.get("region") {
        None => "",
        Some(Value::String(region)) if valid_region(region) => region,
        Some(_) => return Err(CredentialError::Existing),
    };
    Ok(TencentCredentialStatus {
        region: if region.is_empty() {
            "ap-guangzhou"
        } else {
            region
        }
        .to_owned(),
    })
}

fn valid_region(region: &str) -> bool {
    region.len() <= 64
        && region
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'-')
}

pub(crate) fn status_in(directory: &Path) -> Result<ProviderCredentialStatus, CredentialError> {
    let (ai, ai_invalid) = match read_private(&directory.join(AI_FILE)) {
        Ok(None) => (Vec::new(), false),
        Ok(Some(document)) => match ai_status(&document) {
            Ok(ai) => (ai, false),
            Err(_) => (Vec::new(), true),
        },
        Err(CredentialError::Existing) => (Vec::new(), true),
        Err(error) => return Err(error),
    };
    let (tencent, tencent_invalid) = match read_private(&directory.join(TENCENT_FILE)) {
        Ok(None) => (None, false),
        Ok(Some(document)) => match tencent_status(&document) {
            Ok(tencent) => (Some(tencent), false),
            Err(_) => (None, true),
        },
        Err(CredentialError::Existing) => (None, true),
        Err(error) => return Err(error),
    };
    Ok(ProviderCredentialStatus {
        ai,
        ai_invalid,
        tencent,
        tencent_invalid,
    })
}

/// Store the credential for `provider`, bound to `endpoint` and `model`. A `None` token keeps the stored one, so the user can rebind an endpoint or model without pasting the key again.
pub(crate) fn save_ai_in(
    directory: &Path,
    provider: &str,
    endpoint: &str,
    model: &str,
    token: Option<&str>,
) -> Result<(), CredentialError> {
    let _guard = WRITE_LOCK
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    let path = directory.join(AI_FILE);
    let mut entries = match read_private(&path)? {
        Some(document) => ai_entries(&document)?,
        None => AiEntries::new(),
    };
    let provider = trim_pasted(provider);
    let token = match token.map(trim_pasted) {
        Some(token) => token.to_owned(),
        None => entries
            .get(provider)
            .map(|entry| trim_pasted(entry_text(entry, "token")).to_owned())
            .filter(|token| !token.is_empty())
            .ok_or(CredentialError::TokenRequired)?,
    };
    let mut entry = entries.remove(provider).unwrap_or_default();
    entry.insert("provider".into(), Value::String(provider.to_owned()));
    entry.insert(
        "endpoint".into(),
        Value::String(trim_pasted(endpoint).to_owned()),
    );
    entry.insert("model".into(), Value::String(trim_pasted(model).to_owned()));
    entry.insert("token".into(), Value::String(token));
    // Validate the new entry on its own first so the error names what the user just typed rather than an older profile.
    validate_ai_entry(&entry)?;
    entries.insert(provider.to_owned(), entry);
    let document = ai_document(entries).map_err(|error| match error {
        CredentialError::TooManyProfiles => error,
        _ => CredentialError::Existing,
    })?;
    write_private(&path, document.as_ref())
}

pub(crate) fn clear_ai_in(directory: &Path, provider: &str) -> Result<(), CredentialError> {
    let _guard = WRITE_LOCK
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    let path = directory.join(AI_FILE);
    let Some(document) = read_private(&path)? else {
        return Ok(());
    };
    let mut entries = ai_entries(&document)?;
    if entries.remove(trim_pasted(provider)).is_none() {
        return Ok(());
    }
    let document = ai_document(entries).map_err(|_| CredentialError::Existing)?;
    write_private(&path, document.as_ref())
}

/// Store the Tencent Cloud credential. `None` for either secret keeps the stored value, so the region can change without re-entering both.
pub(crate) fn save_tencent_in(
    directory: &Path,
    secret_id: Option<&str>,
    secret_key: Option<&str>,
    region: &str,
) -> Result<(), CredentialError> {
    let _guard = WRITE_LOCK
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    let path = directory.join(TENCENT_FILE);
    let mut document = read_private(&path)?.unwrap_or_default();
    for (key, value) in [("secret_id", secret_id), ("secret_key", secret_key)] {
        let value = match value.map(trim_pasted) {
            Some(value) => value.to_owned(),
            None => trim_pasted(entry_text(&document, key)).to_owned(),
        };
        if value.is_empty() {
            return Err(CredentialError::TokenRequired);
        }
        if !valid_secret(&value) {
            return Err(CredentialError::InvalidSecret);
        }
        document.insert(key.into(), Value::String(value));
    }
    let region = region.trim();
    if !valid_region(region) {
        return Err(CredentialError::InvalidRegion);
    }
    if region.is_empty() {
        document.remove("region");
    } else {
        document.insert("region".into(), Value::String(region.to_owned()));
    }
    write_private(&path, Some(&Value::Object(document)))
}

pub(crate) fn clear_tencent_in(directory: &Path) -> Result<(), CredentialError> {
    let _guard = WRITE_LOCK
        .lock()
        .unwrap_or_else(|poison| poison.into_inner());
    let path = directory.join(TENCENT_FILE);
    // Refuse to delete a file this host would not have written; the user put it there.
    read_private(&path)?;
    write_private(&path, None)
}

async fn run<T, F>(operation: F) -> Result<T, crate::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&Path) -> Result<T, CredentialError> + Send + 'static,
{
    tauri::async_runtime::spawn_blocking(move || {
        let directory = config_directory()?;
        operation(&directory)
    })
    .await
    .map_err(|_| crate::CommandError {
        code: "provider_credentials_storage",
    })?
    .map_err(|error| crate::CommandError { code: error.code() })
}

#[tauri::command]
pub async fn provider_credentials_status() -> Result<ProviderCredentialStatus, crate::CommandError>
{
    run(status_in).await
}

#[tauri::command]
pub async fn save_ai_provider_credential(
    provider: String,
    endpoint: String,
    model: String,
    token: Option<String>,
) -> Result<ProviderCredentialStatus, crate::CommandError> {
    run(move |directory| {
        save_ai_in(directory, &provider, &endpoint, &model, token.as_deref())?;
        status_in(directory)
    })
    .await
}

#[tauri::command]
pub async fn clear_ai_provider_credential(
    provider: String,
) -> Result<ProviderCredentialStatus, crate::CommandError> {
    run(move |directory| {
        clear_ai_in(directory, &provider)?;
        status_in(directory)
    })
    .await
}

#[tauri::command]
pub async fn save_tencent_provider_credential(
    secret_id: Option<String>,
    secret_key: Option<String>,
    region: String,
) -> Result<ProviderCredentialStatus, crate::CommandError> {
    run(move |directory| {
        save_tencent_in(
            directory,
            secret_id.as_deref(),
            secret_key.as_deref(),
            &region,
        )?;
        status_in(directory)
    })
    .await
}

#[tauri::command]
pub async fn clear_tencent_provider_credential(
) -> Result<ProviderCredentialStatus, crate::CommandError> {
    run(|directory| {
        clear_tencent_in(directory)?;
        status_in(directory)
    })
    .await
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn directory() -> tempfile::TempDir {
        tempfile::tempdir().unwrap()
    }

    fn read(path: &Path) -> Value {
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn saves_an_owner_only_ai_profile_the_provider_reads() {
        let temp = directory();
        let root = temp.path().join("msime-client");
        save_ai_in(
            &root,
            "deepseek",
            " https://api.deepseek.com/chat/completions ",
            "deepseek-chat",
            Some(" sk-abc\n"),
        )
        .unwrap();
        let path = root.join(AI_FILE);
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            std::fs::metadata(&root).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert_eq!(
            read(&path),
            serde_json::json!({"profiles": {"deepseek": {
                "endpoint": "https://api.deepseek.com/chat/completions",
                "model": "deepseek-chat",
                "token": "sk-abc"
            }}})
        );
        let status = status_in(&root).unwrap();
        assert_eq!(
            status.ai,
            vec![AiCredentialStatus {
                provider: "deepseek".into(),
                endpoint: "https://api.deepseek.com/chat/completions".into(),
                model: "deepseek-chat".into(),
            }]
        );
        assert!(!status.ai_invalid && status.tencent.is_none());
    }

    #[test]
    fn keeps_the_token_when_rebinding_and_folds_a_top_level_entry() {
        let temp = directory();
        let root = temp.path();
        let path = root.join(AI_FILE);
        std::fs::write(
            &path,
            r#"{"provider":"openai","endpoint":"https://api.openai.com/v1/chat/completions","model":"gpt-4o","token":"sk-old","note":"mine"}"#,
        )
        .unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        save_ai_in(
            root,
            "openai",
            "https://api.openai.com/v1/chat/completions",
            "gpt-4.1",
            None,
        )
        .unwrap();
        save_ai_in(
            root,
            "kimi",
            "https://api.moonshot.cn/v1/chat/completions",
            "kimi-k2",
            Some("sk-kimi"),
        )
        .unwrap();
        let document = read(&path);
        assert_eq!(document["profiles"]["openai"]["token"], "sk-old");
        assert_eq!(document["profiles"]["openai"]["model"], "gpt-4.1");
        assert_eq!(document["profiles"]["openai"]["note"], "mine");
        assert_eq!(document["profiles"]["kimi"]["token"], "sk-kimi");
        assert!(document.get("provider").is_none());
        clear_ai_in(root, "openai").unwrap();
        clear_ai_in(root, "kimi").unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn rejects_what_the_provider_would_refuse() {
        let temp = directory();
        let root = temp.path();
        let save = |endpoint: &str, model: &str, token: Option<&str>| {
            save_ai_in(root, "openai", endpoint, model, token)
        };
        let endpoint = "https://api.openai.com/v1/chat/completions";
        assert_eq!(
            save("http://api.openai.com/v1", "m", Some("sk")),
            Err(CredentialError::InvalidEndpoint)
        );
        assert_eq!(
            save("https://user:pass@api.openai.com/v1", "m", Some("sk")),
            Err(CredentialError::InvalidEndpoint)
        );
        assert_eq!(
            save("https://api.openai.com/v1#x", "m", Some("sk")),
            Err(CredentialError::InvalidEndpoint)
        );
        assert_eq!(
            save(endpoint, " ", Some("sk")),
            Err(CredentialError::InvalidModel)
        );
        assert_eq!(
            save(endpoint, "m", Some("sk key")),
            Err(CredentialError::InvalidToken)
        );
        assert_eq!(
            save(endpoint, "m", Some("<token>")),
            Err(CredentialError::InvalidToken)
        );
        assert_eq!(
            save(endpoint, "m", Some("FAKESECRET_x")),
            Err(CredentialError::InvalidToken)
        );
        assert_eq!(
            save(endpoint, "m", Some("密钥")),
            Err(CredentialError::InvalidToken)
        );
        assert_eq!(
            save(endpoint, "m", None),
            Err(CredentialError::TokenRequired)
        );
        assert_eq!(
            save_ai_in(root, "", endpoint, "m", Some("sk")),
            Err(CredentialError::InvalidProvider)
        );
        assert!(!root.join(AI_FILE).exists());
    }

    #[test]
    fn leaves_a_file_it_did_not_write_alone() {
        let temp = directory();
        let root = temp.path();
        let path = root.join(AI_FILE);
        std::fs::write(&path, r#"{"provider":"openai"}"#).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert_eq!(
            save_ai_in(root, "openai", "https://a.example/v1", "m", Some("sk")),
            Err(CredentialError::Existing)
        );
        assert!(status_in(root).unwrap().ai_invalid);
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        // Owner-only now, but the entry has no token: the provider refuses the whole file, and so does the status.
        assert!(status_in(root).unwrap().ai_invalid);
        assert_eq!(
            save_ai_in(root, "kimi", "https://a.example/v1", "m", Some("sk")),
            Err(CredentialError::Existing)
        );
        // Saving the broken provider itself repairs it.
        save_ai_in(root, "openai", "https://a.example/v1", "m", Some("sk")).unwrap();
        assert!(!status_in(root).unwrap().ai_invalid);

        let link = root.join(TENCENT_FILE);
        std::os::unix::fs::symlink(&path, &link).unwrap();
        assert!(status_in(root).unwrap().tencent_invalid);
        assert_eq!(clear_tencent_in(root), Err(CredentialError::Existing));
        assert!(link.exists());
    }

    #[test]
    fn saves_and_clears_the_tencent_credential() {
        let temp = directory();
        let root = temp.path();
        assert_eq!(
            save_tencent_in(root, None, Some("key"), ""),
            Err(CredentialError::TokenRequired)
        );
        assert_eq!(
            save_tencent_in(root, Some("id"), Some("key"), "AP-Beijing"),
            Err(CredentialError::InvalidRegion)
        );
        assert_eq!(
            save_tencent_in(root, Some("id with space"), Some("key"), ""),
            Err(CredentialError::InvalidSecret)
        );
        save_tencent_in(root, Some(" AKIDexample "), Some("secret"), "").unwrap();
        assert_eq!(
            status_in(root).unwrap().tencent,
            Some(TencentCredentialStatus {
                region: "ap-guangzhou".into()
            })
        );
        save_tencent_in(root, None, None, "ap-shanghai").unwrap();
        let path = root.join(TENCENT_FILE);
        assert_eq!(
            read(&path),
            serde_json::json!({"secret_id": "AKIDexample", "secret_key": "secret", "region": "ap-shanghai"})
        );
        assert_eq!(
            std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
        clear_tencent_in(root).unwrap();
        assert!(!path.exists());
        assert_eq!(status_in(root).unwrap().tencent, None);
    }

    #[test]
    fn caps_the_profile_count_at_the_providers_limit() {
        let temp = directory();
        let root = temp.path();
        for index in 0..MAX_AI_PROFILES {
            save_ai_in(
                root,
                &format!("p{index}"),
                "https://a.example/v1",
                "m",
                Some("sk"),
            )
            .unwrap();
        }
        assert_eq!(
            save_ai_in(root, "one-more", "https://a.example/v1", "m", Some("sk")),
            Err(CredentialError::TooManyProfiles)
        );
        assert_eq!(status_in(root).unwrap().ai.len(), MAX_AI_PROFILES);
    }
}

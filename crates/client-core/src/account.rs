//! Account protocol and session state independent of UI and platform hosts.

use crate::cloud_dictionary::DictionaryKind;
use reqwest::blocking::{Client, Response};
use reqwest::{Method, StatusCode, Url};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::future::Future;
use std::io::{Read, Write};
use std::path::Path;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const ACCOUNT_ORIGIN: &str = "https://api.msime.app";
const MAX_JSON_BYTES: usize = 1024 * 1024;
const MAX_ACCOUNT_PREFERENCE_FIELDS: usize = 512;
const MAX_ACCOUNT_PREFERENCE_KEY_BYTES: usize = 128;
const MAX_ACCOUNT_PREFERENCE_STRING_BYTES: usize = 256 * 1024;
const MAX_DICTIONARY_PAGE_ENTRIES: usize = 100;
const MAX_DICTIONARY_EXPORT_BYTES: usize = 384 * 1024 * 1024;
const MAX_DICTIONARY_SNAPSHOT_BYTES: usize = 512 * 1024 * 1024;
const REFRESH_EARLY_SECONDS: u64 = 30;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountIdentity {
    pub user_id: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountUser {
    pub id: String,
    pub display_name: String,
    pub created_at: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountChallenge {
    pub challenge_id: String,
    pub expires_in: u64,
    pub nonce: Option<String>,
    pub authorization_url: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountProfileIdentity {
    pub provider: String,
    pub subject: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountProfile {
    pub user: AccountUser,
    pub identities: Vec<AccountProfileIdentity>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountClipboardItem {
    pub id: String,
    pub text: String,
    pub updated_at: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountClipboardPage {
    pub enabled: bool,
    pub items: Vec<AccountClipboardItem>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryEntry {
    pub id: String,
    pub kind: DictionaryKind,
    pub code: String,
    pub word: String,
    pub weight: i64,
    pub revision: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryPage {
    pub entries: Vec<AccountDictionaryEntry>,
    pub has_more: bool,
    pub offset: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryCatalogEntry {
    pub kind: DictionaryKind,
    pub code: String,
    pub word: String,
    pub weight: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryCatalogPage {
    pub entries: Vec<AccountDictionaryCatalogEntry>,
    pub has_more: bool,
    pub offset: usize,
    pub revision: i64,
    pub normalized: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountCandidateQuery {
    pub text: String,
    pub kind: String,
    pub scheme: String,
    pub profile: String,
    pub limit: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountPersonalCandidate {
    pub code: String,
    pub word: String,
    pub weight: i64,
    pub canonical_pinyin: Option<String>,
}

impl AccountPersonalCandidate {
    pub fn mutation_code(&self) -> &str {
        self.canonical_pinyin
            .as_deref()
            .filter(|value| !value.is_empty())
            .unwrap_or(&self.code)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountPersonalCandidates {
    pub candidates: Vec<AccountPersonalCandidate>,
    pub context: String,
    pub revision: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountRankingSelection {
    pub count: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountRankingResult {
    pub revision: i64,
    pub changed: bool,
    pub selection: AccountRankingSelection,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountFixedPosition {
    pub context: String,
    pub code: String,
    pub word: String,
    pub position: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountFixedPositions {
    pub positions: Vec<AccountFixedPosition>,
    pub offset: usize,
    pub has_more: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryRevision {
    pub revision: i64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryChange {
    pub revision: i64,
    pub previous: Option<AccountDictionaryEntry>,
    pub replacement: Option<AccountDictionaryEntry>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryChangePage {
    pub changes: Vec<AccountDictionaryChange>,
    pub next: i64,
    pub has_more: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct AccountDictionaryImportResult {
    pub imported: usize,
    pub revision: i64,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct AccountDictionaryExport {
    pub text: String,
    pub filename: String,
}

/// The deliberately small value set accepted by the account preferences API.
/// Credentials, arbitrary JSON objects, and input contents never cross this
/// boundary; platform hosts map their safe local settings to these scalars.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum AccountPreferenceValue {
    Boolean(bool),
    Integer(i64),
    Number(f64),
    String(String),
}

impl AccountPreferenceValue {
    pub fn kind(&self) -> &'static str {
        match self {
            Self::Boolean(_) => "boolean",
            Self::Integer(_) => "integer",
            Self::Number(_) => "number",
            Self::String(_) => "string",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AccountPreferences {
    pub revision: i64,
    pub settings: BTreeMap<String, AccountPreferenceValue>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountPreferenceField {
    #[serde(rename = "type")]
    pub value_type: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountPreferenceSchema {
    pub fields: BTreeMap<String, AccountPreferenceField>,
    pub maximum_bytes: usize,
    pub update_mode: String,
    pub revision_required: bool,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct AccountTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: String,
    pub expires_in: u64,
    pub user: AccountUser,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct SavedAccountSession {
    pub tokens: AccountTokens,
    pub expires_at_unix_ms: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, thiserror::Error)]
pub enum AccountError {
    #[error("invalid account request")]
    Invalid,
    #[error("account authorization is required")]
    Unauthorized,
    #[error("account operation is forbidden")]
    Forbidden,
    #[error("account data changed")]
    Conflict,
    #[error("account resource was not found")]
    NotFound,
    #[error("account request was rate limited")]
    RateLimited,
    #[error("account service is unavailable")]
    Unavailable,
    #[error("secure account storage is unavailable")]
    Storage,
    #[error("account operation was cancelled")]
    Cancelled,
}

impl AccountError {
    pub fn code(&self) -> &'static str {
        match self {
            Self::Invalid => "account_invalid",
            Self::Unauthorized | Self::Forbidden => "account_unauthorized",
            Self::RateLimited => "account_rate_limited",
            Self::Storage => "account_storage",
            Self::Cancelled => "account_cancelled",
            Self::Conflict => "account_conflict",
            Self::NotFound | Self::Unavailable => "account_unavailable",
        }
    }

    fn from_status(status: StatusCode) -> Self {
        match status.as_u16() {
            400 => Self::Invalid,
            401 => Self::Unauthorized,
            403 => Self::Forbidden,
            404 => Self::NotFound,
            409 => Self::Conflict,
            429 => Self::RateLimited,
            503 => Self::Unavailable,
            _ => Self::Unavailable,
        }
    }
}

pub trait AccountApi: Send + Sync + 'static {
    fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError>;
    fn challenge(&self, provider: &str, target: &str) -> Result<AccountChallenge, AccountError>;
    fn login(&self, challenge: &str, credential: &str) -> Result<AccountTokens, AccountError>;
    fn refresh(&self, refresh_token: &str) -> Result<AccountTokens, AccountError>;
    fn profile(&self, access_token: &str) -> Result<AccountProfile, AccountError>;
    fn rename(&self, display_name: &str, access_token: &str) -> Result<(), AccountError>;
    fn logout(&self, access_token: &str, all: bool) -> Result<(), AccountError>;
    fn delete_account(&self, access_token: &str) -> Result<(), AccountError>;

    fn preference_schema(
        &self,
        _access_token: &str,
    ) -> Result<AccountPreferenceSchema, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn preferences(&self, _access_token: &str) -> Result<AccountPreferences, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn put_preferences(
        &self,
        _preferences: &AccountPreferences,
        _access_token: &str,
    ) -> Result<AccountPreferences, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn clipboard(
        &self,
        _search: &str,
        _access_token: &str,
    ) -> Result<AccountClipboardPage, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn set_clipboard_enabled(
        &self,
        _enabled: bool,
        _access_token: &str,
    ) -> Result<(), AccountError> {
        Err(AccountError::Unavailable)
    }

    fn add_clipboard(
        &self,
        _text: &str,
        _access_token: &str,
    ) -> Result<AccountClipboardItem, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn delete_clipboard(&self, _id: Option<&str>, _access_token: &str) -> Result<(), AccountError> {
        Err(AccountError::Unavailable)
    }

    fn dictionary(
        &self,
        _kind: DictionaryKind,
        _search: &str,
        _offset: usize,
        _access_token: &str,
    ) -> Result<AccountDictionaryPage, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn dictionary_catalog(
        &self,
        _kind: DictionaryKind,
        _code: &str,
        _offset: usize,
        _scheme: &str,
        _profile: &str,
        _access_token: &str,
    ) -> Result<AccountDictionaryCatalogPage, AccountError> {
        Err(AccountError::Unavailable)
    }

    #[allow(clippy::too_many_arguments)]
    fn edit_dictionary_catalog(
        &self,
        _kind: DictionaryKind,
        _code: &str,
        _word: &str,
        _revision: i64,
        _replacement: Option<(&str, &str, i64)>,
        _access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn personal_candidates(
        &self,
        _query: &AccountCandidateQuery,
        _access_token: &str,
    ) -> Result<AccountPersonalCandidates, AccountError> {
        Err(AccountError::Unavailable)
    }

    #[allow(clippy::too_many_arguments)]
    fn rank_candidate(
        &self,
        _query: &AccountCandidateQuery,
        _code: &str,
        _word: &str,
        _revision: i64,
        _mode: &str,
        _linear_step: i64,
        _trigger_count: i64,
        _force_top: bool,
        _access_token: &str,
    ) -> Result<AccountRankingResult, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn remove_candidate(
        &self,
        _query: &AccountCandidateQuery,
        _code: &str,
        _word: &str,
        _revision: i64,
        _access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn fixed_positions(
        &self,
        _context: &str,
        _offset: usize,
        _access_token: &str,
    ) -> Result<AccountFixedPositions, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn set_fixed_position(
        &self,
        _context: &str,
        _code: &str,
        _word: &str,
        _position: Option<i64>,
        _revision: i64,
        _access_token: &str,
    ) -> Result<AccountDictionaryRevision, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn add_dictionary(
        &self,
        _kind: DictionaryKind,
        _code: &str,
        _word: &str,
        _weight: i64,
        _access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        Err(AccountError::Unavailable)
    }

    #[allow(clippy::too_many_arguments)]
    fn update_dictionary(
        &self,
        _kind: DictionaryKind,
        _id: &str,
        _code: &str,
        _word: &str,
        _weight: i64,
        _revision: i64,
        _access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn delete_dictionary(
        &self,
        _kind: DictionaryKind,
        _id: &str,
        _revision: i64,
        _access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn import_dictionary(
        &self,
        _kind: DictionaryKind,
        _format: &str,
        _text: &str,
        _access_token: &str,
    ) -> Result<AccountDictionaryImportResult, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn export_dictionary(
        &self,
        _kind: DictionaryKind,
        _format: &str,
        _access_token: &str,
    ) -> Result<AccountDictionaryExport, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn dictionary_changes(
        &self,
        _after: i64,
        _limit: usize,
        _access_token: &str,
    ) -> Result<AccountDictionaryChangePage, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn dictionary_snapshot(&self, _access_token: &str) -> Result<Vec<u8>, AccountError> {
        Err(AccountError::Unavailable)
    }

    fn dictionary_snapshot_to_file(
        &self,
        _destination: &Path,
        _access_token: &str,
    ) -> Result<u64, AccountError> {
        Err(AccountError::Unavailable)
    }
}

pub trait AccountSessionStorage: Send + Sync + 'static {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError>;
    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError>;
    fn clear(&self) -> Result<(), AccountError>;
}

#[derive(Clone)]
pub struct BackendAccountClient {
    client: Client,
    origin: Url,
}

impl BackendAccountClient {
    pub fn new() -> Result<Self, AccountError> {
        Self::with_origin(ACCOUNT_ORIGIN, false)
    }

    fn with_origin(origin: &str, allow_http_loopback: bool) -> Result<Self, AccountError> {
        let origin = Url::parse(origin).map_err(|_| AccountError::Invalid)?;
        let valid_scheme = origin.scheme() == "https"
            || (allow_http_loopback
                && origin.scheme() == "http"
                && origin.host_str() == Some("127.0.0.1"));
        if !valid_scheme
            || origin.cannot_be_a_base()
            || origin.username() != ""
            || origin.password().is_some()
            || origin.query().is_some()
            || origin.fragment().is_some()
        {
            return Err(AccountError::Invalid);
        }
        let client = Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .timeout(Duration::from_secs(30))
            .user_agent("MSIME/Android")
            .build()
            .map_err(|_| AccountError::Unavailable)?;
        Ok(Self { client, origin })
    }

    #[cfg(test)]
    pub(crate) fn loopback(origin: &str) -> Result<Self, AccountError> {
        Self::with_origin(origin, true)
    }

    fn request(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
    ) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit(method, path, token, body, MAX_JSON_BYTES)
    }

    pub(crate) fn request_with_limit(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
        maximum_response_bytes: usize,
    ) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit_timeout(
            method,
            path,
            token,
            body,
            maximum_response_bytes,
            Duration::from_secs(30),
        )
    }

    pub(crate) fn request_with_limit_timeout(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
        maximum_response_bytes: usize,
        timeout: Duration,
    ) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit_timeout_accept(
            method,
            path,
            token,
            body,
            maximum_response_bytes,
            timeout,
            "application/json",
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn request_with_limit_timeout_accept(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<Vec<u8>>,
        maximum_response_bytes: usize,
        timeout: Duration,
        accept: &str,
    ) -> Result<Vec<u8>, AccountError> {
        if !path.starts_with("/v1/") || path.contains('\\') {
            return Err(AccountError::Invalid);
        }
        if body
            .as_ref()
            .is_some_and(|value| value.len() > MAX_JSON_BYTES)
            || token.is_some_and(|value| value.is_empty() || value.chars().any(char::is_whitespace))
        {
            return Err(AccountError::Invalid);
        }
        let url = self.origin.join(path).map_err(|_| AccountError::Invalid)?;
        if url.scheme() != self.origin.scheme()
            || url.host_str() != self.origin.host_str()
            || url.port_or_known_default() != self.origin.port_or_known_default()
            || url.username() != ""
            || url.password().is_some()
            || url.fragment().is_some()
        {
            return Err(AccountError::Invalid);
        }
        let mut request = self
            .client
            .request(method, url)
            .header(reqwest::header::ACCEPT, accept);
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request
                .header(reqwest::header::CONTENT_TYPE, "application/json")
                .body(body);
        }
        let response = request
            .timeout(timeout)
            .send()
            .map_err(|_| AccountError::Unavailable)?;
        read_bounded_response(response, maximum_response_bytes)
    }

    pub(crate) fn json<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request(method, path, token, body)?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    pub(crate) fn json_with_limit<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
        maximum_response_bytes: usize,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request_with_limit(method, path, token, body, maximum_response_bytes)?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    pub(crate) fn json_with_limit_timeout<T: DeserializeOwned, B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
        maximum_response_bytes: usize,
        timeout: Duration,
    ) -> Result<T, AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        let bytes = self.request_with_limit_timeout(
            method,
            path,
            token,
            body,
            maximum_response_bytes,
            timeout,
        )?;
        serde_json::from_slice(&bytes).map_err(|_| AccountError::Unavailable)
    }

    fn empty<B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: Option<&str>,
        body: Option<&B>,
    ) -> Result<(), AccountError> {
        let body = body
            .map(serde_json::to_vec)
            .transpose()
            .map_err(|_| AccountError::Invalid)?;
        self.request(method, path, token, body).map(|_| ())
    }

    pub fn clipboard(
        &self,
        search: &str,
        access_token: &str,
    ) -> Result<AccountClipboardPage, AccountError> {
        validate_clipboard_search(search)?;
        let encoded = percent_encode_query(search);
        let page = self.json::<AccountClipboardPage, ()>(
            Method::GET,
            &format!("/v1/users/me/clipboard?q={encoded}"),
            Some(access_token),
            None,
        )?;
        validate_clipboard_page(&page)?;
        Ok(page)
    }

    pub fn set_clipboard_enabled(
        &self,
        enabled: bool,
        access_token: &str,
    ) -> Result<(), AccountError> {
        #[derive(Serialize)]
        struct Body {
            enabled: bool,
        }
        self.empty(
            Method::PUT,
            "/v1/users/me/clipboard/settings",
            Some(access_token),
            Some(&Body { enabled }),
        )
    }

    pub fn add_clipboard(
        &self,
        text: &str,
        access_token: &str,
    ) -> Result<AccountClipboardItem, AccountError> {
        validate_clipboard_text(text)?;
        #[derive(Serialize)]
        struct Body<'a> {
            text: &'a str,
        }
        let item = self.json(
            Method::POST,
            "/v1/users/me/clipboard",
            Some(access_token),
            Some(&Body { text }),
        )?;
        validate_clipboard_item(&item)?;
        Ok(item)
    }

    pub fn delete_clipboard(
        &self,
        id: Option<&str>,
        access_token: &str,
    ) -> Result<(), AccountError> {
        if let Some(id) = id {
            validate_clipboard_id(id)?;
        }
        let path = id
            .map(|value| format!("/v1/users/me/clipboard/{value}"))
            .unwrap_or_else(|| "/v1/users/me/clipboard".to_owned());
        self.empty::<()>(Method::DELETE, &path, Some(access_token), None)
    }

    pub fn dictionary(
        &self,
        kind: DictionaryKind,
        search: &str,
        offset: usize,
        access_token: &str,
    ) -> Result<AccountDictionaryPage, AccountError> {
        let path = dictionary_path(kind, offset, search)?;
        let page =
            self.json::<AccountDictionaryPage, ()>(Method::GET, &path, Some(access_token), None)?;
        validate_dictionary_page(&page, kind)?;
        Ok(page)
    }

    pub fn dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        offset: usize,
        scheme: &str,
        profile: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryCatalogPage, AccountError> {
        validate_dictionary_catalog_query(code, offset, scheme, profile)?;
        let path = dictionary_catalog_path(kind, code, offset, scheme, profile)?;
        let page = self.json::<AccountDictionaryCatalogPage, ()>(
            Method::GET,
            &path,
            Some(access_token),
            None,
        )?;
        validate_dictionary_catalog_page(&page, kind)?;
        Ok(page)
    }

    pub fn dictionary_changes(
        &self,
        after: i64,
        limit: usize,
        access_token: &str,
    ) -> Result<AccountDictionaryChangePage, AccountError> {
        if after < 0 || !(1..=100).contains(&limit) {
            return Err(AccountError::Invalid);
        }
        let page = self.json::<AccountDictionaryChangePage, ()>(
            Method::GET,
            &format!("/v1/users/me/dictionary/changes?after={after}&limit={limit}"),
            Some(access_token),
            None,
        )?;
        if page.changes.len() > limit {
            return Err(AccountError::Unavailable);
        }
        let mut cursor = after;
        for change in &page.changes {
            if change.revision <= cursor {
                return Err(AccountError::Unavailable);
            }
            if change.previous.as_ref().is_some_and(|entry| {
                validate_dictionary_entry(entry, entry.kind).is_err()
                    || entry.revision > change.revision
            }) || change.replacement.as_ref().is_some_and(|entry| {
                validate_dictionary_entry(entry, entry.kind).is_err()
                    || entry.revision > change.revision
            }) {
                return Err(AccountError::Unavailable);
            }
            cursor = change.revision;
        }
        if page.next != cursor || (page.has_more && page.changes.is_empty()) {
            return Err(AccountError::Unavailable);
        }
        Ok(page)
    }

    pub fn dictionary_snapshot(&self, access_token: &str) -> Result<Vec<u8>, AccountError> {
        self.request_with_limit_timeout_accept(
            Method::GET,
            "/v1/users/me/dictionary/snapshot",
            Some(access_token),
            None,
            MAX_DICTIONARY_SNAPSHOT_BYTES,
            Duration::from_secs(120),
            "application/x-ndjson",
        )
    }

    pub fn dictionary_snapshot_to_file(
        &self,
        destination: &Path,
        access_token: &str,
    ) -> Result<u64, AccountError> {
        if !destination.is_absolute() || !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        let url = self
            .origin
            .join("/v1/users/me/dictionary/snapshot")
            .map_err(|_| AccountError::Invalid)?;
        let mut response = self
            .client
            .get(url)
            .header(reqwest::header::ACCEPT, "application/x-ndjson")
            .bearer_auth(access_token)
            .timeout(Duration::from_secs(120))
            .send()
            .map_err(|_| AccountError::Unavailable)?;
        if !response.status().is_success() {
            return Err(AccountError::from_status(response.status()));
        }
        if response
            .content_length()
            .is_some_and(|length| length > MAX_DICTIONARY_SNAPSHOT_BYTES as u64)
        {
            return Err(AccountError::Unavailable);
        }
        let parent = destination.parent().ok_or(AccountError::Invalid)?;
        if !parent.is_absolute() {
            return Err(AccountError::Invalid);
        }
        let mut temporary = tempfile::Builder::new()
            .prefix("msime-snapshot-")
            .tempfile_in(parent)
            .map_err(|_| AccountError::Unavailable)?;
        let bytes = std::io::copy(
            &mut response
                .by_ref()
                .take((MAX_DICTIONARY_SNAPSHOT_BYTES + 1) as u64),
            temporary.as_file_mut(),
        )
            .map_err(|_| AccountError::Unavailable)?;
        if bytes == 0 || bytes > MAX_DICTIONARY_SNAPSHOT_BYTES as u64 {
            return Err(AccountError::Unavailable);
        }
        temporary
            .as_file_mut()
            .flush()
            .and_then(|_| temporary.as_file().sync_all())
            .map_err(|_| AccountError::Unavailable)?;
        temporary
            .persist(destination)
            .map_err(|_| AccountError::Unavailable)?;
        Ok(bytes)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn edit_dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        revision: i64,
        replacement: Option<(&str, &str, i64)>,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        validate_dictionary_catalog_identity(kind, code, word)?;
        if revision < 0 {
            return Err(AccountError::Invalid);
        }
        if let Some((replacement_code, replacement_word, replacement_weight)) = replacement {
            validate_dictionary_value(
                kind,
                replacement_code,
                replacement_word,
                replacement_weight,
            )?;
        }
        #[derive(Serialize)]
        struct Identity<'a> {
            code: &'a str,
            word: &'a str,
        }
        #[derive(Serialize)]
        struct Body<'a> {
            revision: i64,
            previous: Identity<'a>,
            replacement: Option<Replacement<'a>>,
        }
        #[derive(Serialize)]
        struct Replacement<'a> {
            code: &'a str,
            word: &'a str,
            weight: i64,
        }
        let replacement_body = replacement.map(|(replacement_code, replacement_word, weight)| {
            Replacement {
                code: replacement_code,
                word: replacement_word,
                weight,
            }
        });
        let change = self.json(
            Method::POST,
            &format!(
                "/v1/users/me/dictionaries/{}/edit",
                dictionary_kind_path(kind)
            ),
            Some(access_token),
            Some(&Body {
                revision,
                previous: Identity { code, word },
                replacement: replacement_body,
            }),
        )?;
        validate_dictionary_change(&change, kind)?;
        Ok(change)
    }

    pub fn personal_candidates(
        &self,
        query: &AccountCandidateQuery,
        access_token: &str,
    ) -> Result<AccountPersonalCandidates, AccountError> {
        validate_candidate_query(query)?;
        let result: AccountPersonalCandidates = self.json(
            Method::POST,
            "/v1/users/me/dictionary/candidates",
            Some(access_token),
            Some(query),
        )?;
        validate_personal_candidates(&result)?;
        Ok(result)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn rank_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
        mode: &str,
        linear_step: i64,
        trigger_count: i64,
        force_top: bool,
        access_token: &str,
    ) -> Result<AccountRankingResult, AccountError> {
        validate_candidate_query(query)?;
        validate_candidate_value(query, code, word)?;
        validate_ranking_arguments(query, revision, mode, linear_step, trigger_count)?;
        #[derive(Serialize)]
        struct Action<'a> {
            code: &'a str,
            word: &'a str,
            mode: &'a str,
            linear_step: i64,
            trigger_count: i64,
            force_top: bool,
        }
        #[derive(Serialize)]
        struct Body<'a> {
            revision: i64,
            query: &'a AccountCandidateQuery,
            action: Action<'a>,
        }
        let result = self.json(
            Method::POST,
            "/v1/users/me/dictionary/ranking",
            Some(access_token),
            Some(&Body {
                revision,
                query,
                action: Action {
                    code,
                    word,
                    mode,
                    linear_step,
                    trigger_count,
                    force_top,
                },
            }),
        )?;
        validate_ranking_result(&result)?;
        Ok(result)
    }

    pub fn remove_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        validate_candidate_query(query)?;
        validate_candidate_value(query, code, word)?;
        if revision < 0 || query.kind == "quick" {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body<'a> {
            revision: i64,
            query: &'a AccountCandidateQuery,
            code: &'a str,
            word: &'a str,
        }
        let change = self.json(
            Method::DELETE,
            "/v1/users/me/dictionary/candidates",
            Some(access_token),
            Some(&Body {
                revision,
                query,
                code,
                word,
            }),
        )?;
        validate_dictionary_change(&change, dictionary_kind_for_candidate(query)?)?;
        Ok(change)
    }

    pub fn fixed_positions(
        &self,
        context: &str,
        offset: usize,
        access_token: &str,
    ) -> Result<AccountFixedPositions, AccountError> {
        validate_bounded_text(context, 1024)?;
        if offset > 1_000_000 {
            return Err(AccountError::Invalid);
        }
        let path = format!(
            "/v1/users/me/dictionary/positions?context={}&offset={offset}&limit=100",
            percent_encode_query(context)
        );
        let result = self.json::<AccountFixedPositions, ()>(
            Method::GET,
            &path,
            Some(access_token),
            None,
        )?;
        validate_fixed_positions(&result)?;
        Ok(result)
    }

    pub fn set_fixed_position(
        &self,
        context: &str,
        code: &str,
        word: &str,
        position: Option<i64>,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryRevision, AccountError> {
        validate_bounded_text(context, 1024)?;
        validate_bounded_text(code, 256)?;
        validate_bounded_text(word, 1024)?;
        if revision < 0 || position.is_some_and(|value| !(1..=5).contains(&value)) {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body<'a> {
            context: &'a str,
            code: &'a str,
            word: &'a str,
            position: Option<i64>,
            revision: i64,
        }
        let result: AccountDictionaryRevision = self.json(
            if position.is_some() {
                Method::PUT
            } else {
                Method::DELETE
            },
            "/v1/users/me/dictionary/positions",
            Some(access_token),
            Some(&Body {
                context,
                code,
                word,
                position,
                revision,
            }),
        )?;
        if result.revision < 0 {
            return Err(AccountError::Unavailable);
        }
        Ok(result)
    }

    pub fn add_dictionary(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        weight: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        validate_dictionary_value(kind, code, word, weight)?;
        #[derive(Serialize)]
        struct Body<'a> {
            code: &'a str,
            word: &'a str,
            weight: i64,
        }
        let path = mutation_path(kind, "add").ok_or(AccountError::Invalid)?;
        let change = self.json(
            Method::POST,
            &path,
            Some(access_token),
            Some(&Body { code, word, weight }),
        )?;
        validate_dictionary_change(&change, kind)?;
        Ok(change)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn update_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        code: &str,
        word: &str,
        weight: i64,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        validate_dictionary_id(id)?;
        validate_dictionary_value(kind, code, word, weight)?;
        if revision <= 0 {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body<'a> {
            code: &'a str,
            word: &'a str,
            weight: i64,
            revision: i64,
        }
        let path = format!(
            "/v1/users/me/dictionaries/{}/{}",
            dictionary_kind_path(kind),
            id
        );
        let change = self.json(
            Method::PUT,
            &path,
            Some(access_token),
            Some(&Body {
                code,
                word,
                weight,
                revision,
            }),
        )?;
        validate_dictionary_change(&change, kind)?;
        Ok(change)
    }

    pub fn delete_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        validate_dictionary_id(id)?;
        if revision <= 0 {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body {
            revision: i64,
        }
        let path = format!(
            "/v1/users/me/dictionaries/{}/{}",
            dictionary_kind_path(kind),
            id
        );
        let change = self.json(
            Method::DELETE,
            &path,
            Some(access_token),
            Some(&Body { revision }),
        )?;
        validate_dictionary_change(&change, kind)?;
        Ok(change)
    }

    pub fn import_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
        text: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryImportResult, AccountError> {
        validate_dictionary_import(kind, format, text)?;
        let (path, body) = if format == "hans" {
            (
                mutation_path(kind, "import-hans").ok_or(AccountError::Invalid)?,
                serde_json::json!({ "text": text, "weight": 100000_i64 }),
            )
        } else {
            (
                mutation_path(kind, "import").ok_or(AccountError::Invalid)?,
                serde_json::json!({ "text": text, "format": format }),
            )
        };
        let result = self.json(Method::POST, &path, Some(access_token), Some(&body))?;
        validate_dictionary_import_result(&result)?;
        Ok(result)
    }

    pub fn export_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryExport, AccountError> {
        if !matches!(format, "standard" | "windows") {
            return Err(AccountError::Invalid);
        }
        let path = format!(
            "/v1/users/me/dictionaries/{}/export?format={format}",
            dictionary_kind_path(kind)
        );
        let bytes = self.request_with_limit_timeout_accept(
            Method::GET,
            &path,
            Some(access_token),
            None,
            MAX_DICTIONARY_EXPORT_BYTES,
            Duration::from_secs(600),
            "text/plain",
        )?;
        let text = String::from_utf8(bytes).map_err(|_| AccountError::Unavailable)?;
        if text.is_empty() || text.contains('\0') {
            return Err(AccountError::Unavailable);
        }
        Ok(AccountDictionaryExport {
            text,
            filename: format!("dictionary-{}.tsv", dictionary_kind_path(kind)),
        })
    }
}

fn validate_clipboard_search(value: &str) -> Result<(), AccountError> {
    if value.len() > 1024 || value.chars().any(char::is_control) {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn percent_encode_query(value: &str) -> String {
    let mut encoded = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~') {
            encoded.push(byte as char);
        } else {
            encoded.push('%');
            encoded.push(char::from(b"0123456789ABCDEF"[(byte >> 4) as usize]));
            encoded.push(char::from(b"0123456789ABCDEF"[(byte & 0x0f) as usize]));
        }
    }
    encoded
}

fn validate_clipboard_text(value: &str) -> Result<(), AccountError> {
    if value.trim().is_empty()
        || value.encode_utf16().count() > 4000
        || value.contains('\0')
        || value
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_clipboard_id(value: &str) -> Result<(), AccountError> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_clipboard_item(value: &AccountClipboardItem) -> Result<(), AccountError> {
    validate_clipboard_id(&value.id)?;
    validate_clipboard_text(&value.text)?;
    if value.updated_at.is_empty()
        || value.updated_at.len() > 128
        || value.updated_at.chars().any(char::is_control)
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

fn validate_clipboard_page(value: &AccountClipboardPage) -> Result<(), AccountError> {
    if value.items.len() > 50 {
        return Err(AccountError::Unavailable);
    }
    for item in &value.items {
        validate_clipboard_item(item)?;
    }
    Ok(())
}

fn dictionary_kind_path(kind: DictionaryKind) -> &'static str {
    match kind {
        DictionaryKind::Pinyin => "pinyin",
        DictionaryKind::Wubi => "wubi",
        DictionaryKind::Quick => "quick",
        DictionaryKind::English => "english",
    }
}

fn dictionary_path(
    kind: DictionaryKind,
    offset: usize,
    search: &str,
) -> Result<String, AccountError> {
    if offset > 1_000_000 || search.len() > 1024 || search.chars().any(char::is_control) {
        return Err(AccountError::Invalid);
    }
    Ok(format!(
        "/v1/users/me/dictionaries/{}?q={}&offset={offset}&limit=100",
        dictionary_kind_path(kind),
        percent_encode_query(search)
    ))
}

fn validate_dictionary_catalog_query(
    code: &str,
    offset: usize,
    scheme: &str,
    profile: &str,
) -> Result<(), AccountError> {
    if offset > 1_000_000
        || code.len() > 256
        || code.contains('\0')
        || scheme.is_empty()
        || scheme.len() > 64
        || profile.is_empty()
        || profile.len() > 64
        || scheme.chars().any(char::is_control)
        || profile.chars().any(char::is_control)
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn dictionary_catalog_path(
    kind: DictionaryKind,
    code: &str,
    offset: usize,
    scheme: &str,
    profile: &str,
) -> Result<String, AccountError> {
    validate_dictionary_catalog_query(code, offset, scheme, profile)?;
    Ok(format!(
        "/v1/users/me/dictionaries/{}/catalog?q={}&offset={offset}&limit=100&scheme={}&profile={}",
        dictionary_kind_path(kind),
        percent_encode_query(code),
        percent_encode_query(scheme),
        percent_encode_query(profile)
    ))
}

fn validate_dictionary_catalog_identity(
    kind: DictionaryKind,
    code: &str,
    word: &str,
) -> Result<(), AccountError> {
    let code_ok = match kind {
        DictionaryKind::Pinyin => code
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || matches!(byte, b'\'' | b' ')),
        DictionaryKind::Wubi => code.bytes().all(|byte| byte.is_ascii_lowercase()),
        DictionaryKind::Quick => code
            .bytes()
            .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit()),
        DictionaryKind::English => code.bytes().all(|byte| byte.is_ascii_alphabetic()),
    };
    if !code_ok
        || code.is_empty()
        || code.len() > 256
        || word.is_empty()
        || word.len() > 1024
        || code.chars().any(char::is_control)
        || word.chars().any(char::is_control)
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_dictionary_catalog_entry(
    entry: &AccountDictionaryCatalogEntry,
    expected_kind: DictionaryKind,
) -> Result<(), AccountError> {
    if entry.kind != expected_kind {
        return Err(AccountError::Unavailable);
    }
    validate_dictionary_value(expected_kind, &entry.code, &entry.word, entry.weight)
        .map_err(|_| AccountError::Unavailable)
}

fn validate_dictionary_catalog_page(
    page: &AccountDictionaryCatalogPage,
    expected_kind: DictionaryKind,
) -> Result<(), AccountError> {
    if page.entries.len() > MAX_DICTIONARY_PAGE_ENTRIES
        || page.offset > 1_000_000
        || page.revision < 0
        || page.normalized.len() > 256
        || page.normalized.chars().any(char::is_control)
    {
        return Err(AccountError::Unavailable);
    }
    for entry in &page.entries {
        validate_dictionary_catalog_entry(entry, expected_kind)?;
    }
    Ok(())
}

fn validate_bounded_text(value: &str, maximum_bytes: usize) -> Result<(), AccountError> {
    if value.len() > maximum_bytes || value.chars().any(char::is_control) {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_candidate_query(query: &AccountCandidateQuery) -> Result<(), AccountError> {
    if query.text.is_empty()
        || query.text.len() > 256
        || query.text.chars().any(char::is_control)
        || !matches!(
            query.kind.as_str(),
            "pinyin" | "jianpin" | "wubi" | "quick" | "english"
        )
        || !matches!(query.scheme.as_str(), "pinyin" | "shuangpin")
        || !matches!(
            query.profile.as_str(),
            "xiaohe" | "ziranma" | "microsoft" | "shoudao"
        )
        || !(1..=100).contains(&query.limit)
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn dictionary_kind_for_candidate(
    query: &AccountCandidateQuery,
) -> Result<DictionaryKind, AccountError> {
    match query.kind.as_str() {
        "pinyin" | "jianpin" => Ok(DictionaryKind::Pinyin),
        "wubi" => Ok(DictionaryKind::Wubi),
        "quick" => Ok(DictionaryKind::Quick),
        "english" => Ok(DictionaryKind::English),
        _ => Err(AccountError::Invalid),
    }
}

fn validate_candidate_value(
    query: &AccountCandidateQuery,
    code: &str,
    word: &str,
) -> Result<(), AccountError> {
    validate_bounded_text(code, 256)?;
    validate_bounded_text(word, 1024)?;
    if code.is_empty() || word.is_empty() || (query.kind == "quick" && word.encode_utf16().count() > 199) {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_ranking_arguments(
    query: &AccountCandidateQuery,
    revision: i64,
    mode: &str,
    linear_step: i64,
    trigger_count: i64,
) -> Result<(), AccountError> {
    if revision < 0
        || query.kind == "quick"
        || !matches!(mode, "disabled" | "pin" | "halve" | "linear" | "promote")
        || !(1..=100).contains(&linear_step)
        || !(1..=10).contains(&trigger_count)
    {
        Err(AccountError::Invalid)
    } else {
        Ok(())
    }
}

fn validate_personal_candidates(result: &AccountPersonalCandidates) -> Result<(), AccountError> {
    if result.candidates.len() > 100
        || result.revision < 0
        || result.context.len() > 1024
        || result.context.chars().any(char::is_control)
    {
        return Err(AccountError::Unavailable);
    }
    for candidate in &result.candidates {
        validate_bounded_text(&candidate.code, 256).map_err(|_| AccountError::Unavailable)?;
        validate_bounded_text(&candidate.word, 1024).map_err(|_| AccountError::Unavailable)?;
        if candidate.code.is_empty() || candidate.word.is_empty() || candidate.weight < 0 {
            return Err(AccountError::Unavailable);
        }
        if let Some(canonical) = candidate.canonical_pinyin.as_deref() {
            validate_bounded_text(canonical, 256).map_err(|_| AccountError::Unavailable)?;
        }
    }
    Ok(())
}

fn validate_ranking_result(result: &AccountRankingResult) -> Result<(), AccountError> {
    if result.revision < 0 || result.selection.count < 0 {
        Err(AccountError::Unavailable)
    } else {
        Ok(())
    }
}

fn validate_fixed_positions(result: &AccountFixedPositions) -> Result<(), AccountError> {
    if result.positions.len() > 100 || result.offset > 1_000_000 {
        return Err(AccountError::Unavailable);
    }
    for item in &result.positions {
        validate_bounded_text(&item.context, 1024).map_err(|_| AccountError::Unavailable)?;
        validate_bounded_text(&item.code, 256).map_err(|_| AccountError::Unavailable)?;
        validate_bounded_text(&item.word, 1024).map_err(|_| AccountError::Unavailable)?;
        if item.position <= 0 || item.position > 5 {
            return Err(AccountError::Unavailable);
        }
    }
    Ok(())
}

fn mutation_path(kind: DictionaryKind, operation: &str) -> Option<String> {
    matches!(operation, "add" | "import" | "import-hans" | "export").then(|| {
        format!(
            "/v1/users/me/dictionaries/{}/{}",
            dictionary_kind_path(kind),
            operation
        )
    })
}

fn validate_dictionary_id(value: &str) -> Result<(), AccountError> {
    if value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    {
        Ok(())
    } else {
        Err(AccountError::Invalid)
    }
}

fn validate_dictionary_value(
    kind: DictionaryKind,
    code: &str,
    word: &str,
    weight: i64,
) -> Result<(), AccountError> {
    let (code_ok, code_limit) = match kind {
        DictionaryKind::Pinyin => (
            code.bytes()
                .all(|byte| byte.is_ascii_lowercase() || matches!(byte, b'\'' | b' ')),
            256,
        ),
        DictionaryKind::Wubi => (code.bytes().all(|byte| byte.is_ascii_lowercase()), 4),
        DictionaryKind::Quick => (
            code.bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit()),
            32,
        ),
        DictionaryKind::English => (code.bytes().all(|byte| byte.is_ascii_alphabetic()), 64),
    };
    if !code_ok
        || code.is_empty()
        || code.len() > code_limit
        || word.is_empty()
        || word.len() > 1024
        || weight < 0
        || code.chars().any(char::is_control)
        || word.chars().any(char::is_control)
        || (kind == DictionaryKind::Quick && word.encode_utf16().count() > 199)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_dictionary_entry(
    entry: &AccountDictionaryEntry,
    expected_kind: DictionaryKind,
) -> Result<(), AccountError> {
    if entry.kind != expected_kind || entry.revision <= 0 {
        return Err(AccountError::Unavailable);
    }
    validate_dictionary_id(&entry.id).map_err(|_| AccountError::Unavailable)?;
    validate_dictionary_value(expected_kind, &entry.code, &entry.word, entry.weight)
        .map_err(|_| AccountError::Unavailable)
}

fn validate_dictionary_page(
    page: &AccountDictionaryPage,
    expected_kind: DictionaryKind,
) -> Result<(), AccountError> {
    if page.entries.len() > MAX_DICTIONARY_PAGE_ENTRIES || page.offset > 1_000_000 {
        return Err(AccountError::Unavailable);
    }
    for entry in &page.entries {
        validate_dictionary_entry(entry, expected_kind)?;
    }
    Ok(())
}

fn validate_dictionary_change(
    change: &AccountDictionaryChange,
    expected_kind: DictionaryKind,
) -> Result<(), AccountError> {
    if change.revision <= 0
        || change
            .previous
            .as_ref()
            .is_some_and(|entry| validate_dictionary_entry(entry, expected_kind).is_err())
        || change
            .replacement
            .as_ref()
            .is_some_and(|entry| validate_dictionary_entry(entry, expected_kind).is_err())
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

fn validate_dictionary_import(
    kind: DictionaryKind,
    format: &str,
    text: &str,
) -> Result<(), AccountError> {
    if !matches!(format, "standard" | "windows" | "hans")
        || (format == "hans" && kind != DictionaryKind::Pinyin)
        || text.is_empty()
        || text.len() > 64 * 1024
        || text.contains('\0')
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_dictionary_import_result(
    result: &AccountDictionaryImportResult,
) -> Result<(), AccountError> {
    if result.imported > 1_000_000 || result.revision < 0 {
        Err(AccountError::Unavailable)
    } else {
        Ok(())
    }
}

fn read_bounded_response(
    mut response: Response,
    maximum_response_bytes: usize,
) -> Result<Vec<u8>, AccountError> {
    if !response.status().is_success() {
        return Err(AccountError::from_status(response.status()));
    }
    if response
        .content_length()
        .is_some_and(|length| length > maximum_response_bytes as u64)
    {
        return Err(AccountError::Unavailable);
    }
    let mut bytes = Vec::new();
    response
        .by_ref()
        .take((maximum_response_bytes + 1) as u64)
        .read_to_end(&mut bytes)
        .map_err(|_| AccountError::Unavailable)?;
    if bytes.len() > maximum_response_bytes {
        return Err(AccountError::Unavailable);
    }
    Ok(bytes)
}

impl AccountApi for BackendAccountClient {
    fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError> {
        #[derive(Deserialize)]
        struct Providers {
            providers: std::collections::HashMap<String, bool>,
        }
        self.json::<Providers, ()>(Method::GET, "/v1/auth/providers", None, None)
            .map(|value| value.providers)
    }

    fn challenge(&self, provider: &str, target: &str) -> Result<AccountChallenge, AccountError> {
        validate_provider_target(provider, target)?;
        #[derive(Serialize)]
        struct Body<'a> {
            provider: &'a str,
            target: &'a str,
            purpose: &'static str,
        }
        let challenge = self.json(
            Method::POST,
            "/v1/auth/challenges",
            None,
            Some(&Body {
                provider,
                target,
                purpose: "login",
            }),
        )?;
        validate_challenge(&challenge)?;
        Ok(challenge)
    }

    fn login(&self, challenge: &str, credential: &str) -> Result<AccountTokens, AccountError> {
        validate_login(challenge, credential)?;
        #[derive(Serialize)]
        struct Body<'a> {
            challenge_id: &'a str,
            credential: &'a str,
        }
        let tokens = self.json(
            Method::POST,
            "/v1/auth/login",
            None,
            Some(&Body {
                challenge_id: challenge,
                credential,
            }),
        )?;
        validate_tokens(&tokens)?;
        Ok(tokens)
    }

    fn refresh(&self, refresh_token: &str) -> Result<AccountTokens, AccountError> {
        if !valid_token(refresh_token) {
            return Err(AccountError::Invalid);
        }
        #[derive(Serialize)]
        struct Body<'a> {
            refresh_token: &'a str,
        }
        let tokens = self.json(
            Method::POST,
            "/v1/auth/refresh",
            None,
            Some(&Body { refresh_token }),
        )?;
        validate_tokens(&tokens)?;
        Ok(tokens)
    }

    fn profile(&self, access_token: &str) -> Result<AccountProfile, AccountError> {
        if !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        let profile =
            self.json::<AccountProfile, ()>(Method::GET, "/v1/users/me", Some(access_token), None)?;
        validate_profile(&profile)?;
        Ok(profile)
    }

    fn rename(&self, display_name: &str, access_token: &str) -> Result<(), AccountError> {
        validate_display_name(display_name)?;
        #[derive(Serialize)]
        struct Body<'a> {
            display_name: &'a str,
        }
        self.empty(
            Method::PATCH,
            "/v1/users/me",
            Some(access_token),
            Some(&Body { display_name }),
        )
    }

    fn logout(&self, access_token: &str, all: bool) -> Result<(), AccountError> {
        #[derive(Serialize)]
        struct Body {
            all: bool,
        }
        self.empty(
            Method::POST,
            "/v1/auth/logout",
            Some(access_token),
            Some(&Body { all }),
        )
    }

    fn delete_account(&self, access_token: &str) -> Result<(), AccountError> {
        self.empty::<()>(Method::DELETE, "/v1/users/me", Some(access_token), None)
    }

    fn preference_schema(
        &self,
        access_token: &str,
    ) -> Result<AccountPreferenceSchema, AccountError> {
        if !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        let schema = self.json::<AccountPreferenceSchema, ()>(
            Method::GET,
            "/v1/users/me/preferences/schema",
            Some(access_token),
            None,
        )?;
        validate_preference_schema(&schema)?;
        Ok(schema)
    }

    fn preferences(&self, access_token: &str) -> Result<AccountPreferences, AccountError> {
        if !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        let preferences = self.json::<AccountPreferences, ()>(
            Method::GET,
            "/v1/users/me/preferences",
            Some(access_token),
            None,
        )?;
        validate_account_preferences(&preferences)?;
        Ok(preferences)
    }

    fn put_preferences(
        &self,
        preferences: &AccountPreferences,
        access_token: &str,
    ) -> Result<AccountPreferences, AccountError> {
        if !valid_token(access_token) {
            return Err(AccountError::Invalid);
        }
        validate_account_preferences(preferences)?;
        let updated = self.json(
            Method::PUT,
            "/v1/users/me/preferences",
            Some(access_token),
            Some(preferences),
        )?;
        validate_account_preferences(&updated)?;
        Ok(updated)
    }

    fn clipboard(
        &self,
        search: &str,
        access_token: &str,
    ) -> Result<AccountClipboardPage, AccountError> {
        self.clipboard(search, access_token)
    }

    fn set_clipboard_enabled(&self, enabled: bool, access_token: &str) -> Result<(), AccountError> {
        self.set_clipboard_enabled(enabled, access_token)
    }

    fn add_clipboard(
        &self,
        text: &str,
        access_token: &str,
    ) -> Result<AccountClipboardItem, AccountError> {
        self.add_clipboard(text, access_token)
    }

    fn delete_clipboard(&self, id: Option<&str>, access_token: &str) -> Result<(), AccountError> {
        self.delete_clipboard(id, access_token)
    }

    fn dictionary(
        &self,
        kind: DictionaryKind,
        search: &str,
        offset: usize,
        access_token: &str,
    ) -> Result<AccountDictionaryPage, AccountError> {
        self.dictionary(kind, search, offset, access_token)
    }

    fn dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        offset: usize,
        scheme: &str,
        profile: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryCatalogPage, AccountError> {
        self.dictionary_catalog(kind, code, offset, scheme, profile, access_token)
    }

    #[allow(clippy::too_many_arguments)]
    fn edit_dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        revision: i64,
        replacement: Option<(&str, &str, i64)>,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.edit_dictionary_catalog(kind, code, word, revision, replacement, access_token)
    }

    fn personal_candidates(
        &self,
        query: &AccountCandidateQuery,
        access_token: &str,
    ) -> Result<AccountPersonalCandidates, AccountError> {
        self.personal_candidates(query, access_token)
    }

    #[allow(clippy::too_many_arguments)]
    fn rank_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
        mode: &str,
        linear_step: i64,
        trigger_count: i64,
        force_top: bool,
        access_token: &str,
    ) -> Result<AccountRankingResult, AccountError> {
        self.rank_candidate(
            query,
            code,
            word,
            revision,
            mode,
            linear_step,
            trigger_count,
            force_top,
            access_token,
        )
    }

    fn remove_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.remove_candidate(query, code, word, revision, access_token)
    }

    fn fixed_positions(
        &self,
        context: &str,
        offset: usize,
        access_token: &str,
    ) -> Result<AccountFixedPositions, AccountError> {
        self.fixed_positions(context, offset, access_token)
    }

    fn set_fixed_position(
        &self,
        context: &str,
        code: &str,
        word: &str,
        position: Option<i64>,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryRevision, AccountError> {
        self.set_fixed_position(context, code, word, position, revision, access_token)
    }

    fn add_dictionary(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        weight: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.add_dictionary(kind, code, word, weight, access_token)
    }

    fn update_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        code: &str,
        word: &str,
        weight: i64,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.update_dictionary(kind, id, code, word, weight, revision, access_token)
    }

    fn delete_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        revision: i64,
        access_token: &str,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.delete_dictionary(kind, id, revision, access_token)
    }

    fn import_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
        text: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryImportResult, AccountError> {
        self.import_dictionary(kind, format, text, access_token)
    }

    fn export_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
        access_token: &str,
    ) -> Result<AccountDictionaryExport, AccountError> {
        self.export_dictionary(kind, format, access_token)
    }

    fn dictionary_changes(
        &self,
        after: i64,
        limit: usize,
        access_token: &str,
    ) -> Result<AccountDictionaryChangePage, AccountError> {
        self.dictionary_changes(after, limit, access_token)
    }

    fn dictionary_snapshot(&self, access_token: &str) -> Result<Vec<u8>, AccountError> {
        self.dictionary_snapshot(access_token)
    }

    fn dictionary_snapshot_to_file(
        &self,
        destination: &Path,
        access_token: &str,
    ) -> Result<u64, AccountError> {
        self.dictionary_snapshot_to_file(destination, access_token)
    }
}

pub fn validate_account_preferences(value: &AccountPreferences) -> Result<(), AccountError> {
    if value.revision < 0 || value.settings.len() > MAX_ACCOUNT_PREFERENCE_FIELDS {
        return Err(AccountError::Unavailable);
    }
    for (key, value) in &value.settings {
        if !valid_preference_key(key) {
            return Err(AccountError::Unavailable);
        }
        match value {
            AccountPreferenceValue::Number(number) if !number.is_finite() => {
                return Err(AccountError::Unavailable);
            }
            AccountPreferenceValue::String(string)
                if string.len() > MAX_ACCOUNT_PREFERENCE_STRING_BYTES
                    || string.chars().any(char::is_control) =>
            {
                return Err(AccountError::Unavailable);
            }
            _ => {}
        }
    }
    Ok(())
}

pub fn validate_preference_schema(value: &AccountPreferenceSchema) -> Result<(), AccountError> {
    if value.fields.len() > MAX_ACCOUNT_PREFERENCE_FIELDS
        || !(1..=MAX_JSON_BYTES).contains(&value.maximum_bytes)
        || value.update_mode != "replace"
        || !value.revision_required
    {
        return Err(AccountError::Unavailable);
    }
    for (key, field) in &value.fields {
        if !valid_preference_key(key)
            || !matches!(
                field.value_type.as_str(),
                "boolean" | "integer" | "number" | "string"
            )
        {
            return Err(AccountError::Unavailable);
        }
    }
    Ok(())
}

/// Merge a host's supported values into a previously downloaded cloud
/// snapshot. Unknown platform fields are intentionally retained, while a
/// caller that tries to write an unknown or incorrectly typed field is rejected.
pub fn merge_account_preferences(
    base: &AccountPreferences,
    replacing: &BTreeMap<String, AccountPreferenceValue>,
    schema: &AccountPreferenceSchema,
) -> Result<AccountPreferences, AccountError> {
    validate_account_preferences(base)?;
    validate_preference_schema(schema)?;
    if base.revision < 0 {
        return Err(AccountError::Invalid);
    }
    let mut settings = base.settings.clone();
    for (key, value) in replacing {
        let field = schema.fields.get(key).ok_or(AccountError::Invalid)?;
        if field.value_type != value.kind()
            && !(field.value_type == "number" && value.kind() == "integer")
        {
            return Err(AccountError::Invalid);
        }
        settings.insert(key.clone(), value.clone());
    }
    let merged = AccountPreferences {
        revision: base.revision,
        settings,
    };
    validate_account_preferences(&merged)?;
    let bytes = serde_json::to_vec(&merged).map_err(|_| AccountError::Invalid)?;
    if bytes.len() > schema.maximum_bytes.min(MAX_JSON_BYTES) {
        return Err(AccountError::Invalid);
    }
    Ok(merged)
}

fn valid_preference_key(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= MAX_ACCOUNT_PREFERENCE_KEY_BYTES
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'_' | b'-'))
}

fn validate_provider_target(provider: &str, target: &str) -> Result<(), AccountError> {
    if !matches!(provider, "email" | "phone")
        || target.is_empty()
        || target.len() > 320
        || target.trim() != target
        || target.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_challenge(challenge: &AccountChallenge) -> Result<(), AccountError> {
    if challenge.challenge_id.is_empty()
        || challenge.challenge_id.len() > 256
        || challenge.challenge_id.chars().any(char::is_control)
        || challenge.expires_in == 0
        || challenge
            .nonce
            .as_ref()
            .is_some_and(|value| value.len() > 4096 || value.chars().any(char::is_control))
        || challenge
            .authorization_url
            .as_ref()
            .is_some_and(|value| value.len() > 4096 || value.chars().any(char::is_control))
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

fn validate_login(challenge: &str, credential: &str) -> Result<(), AccountError> {
    if challenge.is_empty()
        || challenge.len() > 256
        || challenge.chars().any(char::is_control)
        || credential.len() != 6
        || !credential.bytes().all(|byte| byte.is_ascii_digit())
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_display_name(value: &str) -> Result<(), AccountError> {
    if value.is_empty()
        || value.trim() != value
        || value.chars().count() > 64
        || value.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_tokens(tokens: &AccountTokens) -> Result<(), AccountError> {
    if tokens.token_type != "Bearer"
        || tokens.expires_in == 0
        || !valid_token(&tokens.access_token)
        || !valid_token(&tokens.refresh_token)
    {
        return Err(AccountError::Unavailable);
    }
    validate_user(&tokens.user).map_err(|_| AccountError::Unavailable)
}

fn valid_token(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn validate_user(user: &AccountUser) -> Result<(), AccountError> {
    validate_identity(&AccountIdentity {
        user_id: user.id.clone(),
    })
    .map_err(|_| AccountError::Invalid)?;
    if user.display_name.chars().count() > 64
        || user.display_name.chars().any(char::is_control)
        || user.created_at.len() > 128
        || user.created_at.chars().any(char::is_control)
    {
        return Err(AccountError::Invalid);
    }
    Ok(())
}

fn validate_profile(profile: &AccountProfile) -> Result<(), AccountError> {
    validate_user(&profile.user)?;
    if profile.identities.len() > 16
        || profile.identities.iter().any(|identity| {
            identity.provider.is_empty()
                || identity.provider.len() > 32
                || !identity
                    .provider
                    .bytes()
                    .all(|byte| byte.is_ascii_lowercase() || byte == b'_' || byte == b'-')
                || identity.subject.len() > 512
                || identity.subject.chars().any(char::is_control)
        })
    {
        return Err(AccountError::Unavailable);
    }
    Ok(())
}

pub fn validate_identity(identity: &AccountIdentity) -> Result<(), &'static str> {
    if identity.user_id.is_empty()
        || identity.user_id.len() > 256
        || identity.user_id.chars().any(char::is_control)
    {
        return Err("invalid account identity");
    }
    Ok(())
}

struct SessionState {
    loaded: bool,
    saved: Option<SavedAccountSession>,
    generation: u64,
    refresh: Option<Arc<RefreshFlight>>,
}

struct RefreshFlight {
    result: Mutex<Option<Result<String, AccountError>>>,
    ready: Condvar,
}

impl RefreshFlight {
    fn new() -> Self {
        Self {
            result: Mutex::new(None),
            ready: Condvar::new(),
        }
    }

    fn finish(&self, result: Result<String, AccountError>) {
        if let Ok(mut slot) = self.result.lock() {
            *slot = Some(result);
            self.ready.notify_all();
        }
    }

    fn wait(&self) -> Result<String, AccountError> {
        let mut slot = self.result.lock().map_err(|_| AccountError::Unavailable)?;
        while slot.is_none() {
            slot = self
                .ready
                .wait(slot)
                .map_err(|_| AccountError::Unavailable)?;
        }
        slot.clone().ok_or(AccountError::Unavailable)?
    }
}

pub struct BackendAccountSession<A: AccountApi, S: AccountSessionStorage> {
    api: A,
    storage: S,
    state: Mutex<SessionState>,
}

impl<A: AccountApi, S: AccountSessionStorage> BackendAccountSession<A, S> {
    pub fn new(api: A, storage: S) -> Self {
        Self {
            api,
            storage,
            state: Mutex::new(SessionState {
                loaded: false,
                saved: None,
                generation: 0,
                refresh: None,
            }),
        }
    }

    fn lock(&self) -> Result<MutexGuard<'_, SessionState>, AccountError> {
        self.state.lock().map_err(|_| AccountError::Unavailable)
    }

    fn load_locked(&self, state: &mut SessionState) -> Result<(), AccountError> {
        if !state.loaded {
            let saved = self.storage.load()?;
            if let Some(value) = &saved {
                validate_tokens(&value.tokens).map_err(|_| AccountError::Storage)?;
            }
            state.saved = saved;
            state.loaded = true;
        }
        Ok(())
    }

    pub fn status(&self) -> Result<Option<AccountUser>, AccountError> {
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        Ok(state.saved.as_ref().map(|saved| saved.tokens.user.clone()))
    }

    pub fn providers(&self) -> Result<std::collections::HashMap<String, bool>, AccountError> {
        self.api.providers()
    }

    pub fn request_code(
        &self,
        provider: &str,
        target: &str,
    ) -> Result<AccountChallenge, AccountError> {
        validate_provider_target(provider, target)?;
        self.api.challenge(provider, target)
    }

    pub fn sign_in(&self, challenge: &str, credential: &str) -> Result<AccountUser, AccountError> {
        validate_login(challenge, credential)?;
        let version = {
            let mut state = self.lock()?;
            state.generation = state.generation.wrapping_add(1);
            state.refresh = None;
            state.generation
        };
        let tokens = self.api.login(challenge, credential)?;
        validate_tokens(&tokens)?;
        let value = saved_session(tokens)?;
        let user = value.tokens.user.clone();
        let mut state = self.lock()?;
        if state.generation != version {
            return Err(AccountError::Cancelled);
        }
        self.storage.save(&value)?;
        state.saved = Some(value);
        state.loaded = true;
        Ok(user)
    }

    pub fn access_token(&self, rejected_token: Option<&str>) -> Result<String, AccountError> {
        let (flight, version, refresh_token) = {
            let mut state = self.lock()?;
            self.load_locked(&mut state)?;
            let current = state.saved.as_ref().ok_or(AccountError::Unauthorized)?;
            if current.expires_at_unix_ms > refresh_deadline_ms()
                && rejected_token != Some(current.tokens.access_token.as_str())
            {
                return Ok(current.tokens.access_token.clone());
            }
            if let Some(flight) = &state.refresh {
                let flight = Arc::clone(flight);
                drop(state);
                return flight.wait();
            }
            let version = state.generation;
            let refresh_token = current.tokens.refresh_token.clone();
            let flight = Arc::new(RefreshFlight::new());
            state.refresh = Some(Arc::clone(&flight));
            (flight, version, refresh_token)
        };

        let api_result = self.api.refresh(&refresh_token);
        let result = {
            let mut state = self.lock()?;
            let result = if state.generation != version {
                Err(AccountError::Cancelled)
            } else {
                match api_result {
                    Ok(tokens) => {
                        match validate_tokens(&tokens).and_then(|_| saved_session(tokens)) {
                            Ok(value) => match self.storage.save(&value) {
                                Ok(()) => {
                                    let token = value.tokens.access_token.clone();
                                    state.saved = Some(value);
                                    state.loaded = true;
                                    Ok(token)
                                }
                                Err(error) => Err(error),
                            },
                            Err(error) => Err(error),
                        }
                    }
                    Err(AccountError::Unauthorized) => {
                        state.saved = None;
                        state.loaded = true;
                        self.storage.clear().and(Err(AccountError::Unauthorized))
                    }
                    Err(error) => Err(error),
                }
            };
            if state
                .refresh
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, &flight))
            {
                state.refresh = None;
            }
            result
        };
        flight.finish(result.clone());
        result
    }

    pub fn credentials(
        &self,
        rejected_token: Option<&str>,
        expected_user_id: Option<&str>,
    ) -> Result<(String, String), AccountError> {
        {
            let mut state = self.lock()?;
            self.load_locked(&mut state)?;
            if expected_user_id.is_some_and(|expected| {
                state
                    .saved
                    .as_ref()
                    .map(|saved| saved.tokens.user.id.as_str())
                    != Some(expected)
            }) {
                return Err(AccountError::Cancelled);
            }
        }
        let token = self.access_token(rejected_token)?;
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        let saved = state.saved.as_ref().ok_or(AccountError::Cancelled)?;
        if saved.tokens.access_token != token
            || expected_user_id.is_some_and(|expected| saved.tokens.user.id != expected)
        {
            return Err(AccountError::Cancelled);
        }
        Ok((saved.tokens.user.id.clone(), token))
    }

    pub fn profile(&self) -> Result<AccountProfile, AccountError> {
        let (user_id, token) = self.credentials(None, None)?;
        let profile = match self.api.profile(&token) {
            Err(AccountError::Unauthorized) => {
                let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
                self.api.profile(&replacement)?
            }
            result => result?,
        };
        validate_profile(&profile)?;
        if profile.user.id != user_id {
            return Err(AccountError::Cancelled);
        }
        self.update_user(profile.user.clone())?;
        Ok(profile)
    }

    pub fn rename(&self, display_name: &str) -> Result<AccountProfile, AccountError> {
        validate_display_name(display_name)?;
        let (user_id, token) = self.credentials(None, None)?;
        if let Err(error) = self.api.rename(display_name, &token) {
            if error != AccountError::Unauthorized {
                return Err(error);
            }
            let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
            self.api.rename(display_name, &replacement)?;
        }
        self.profile()
    }

    pub fn logout(&self, all: bool) -> Result<(), AccountError> {
        let token = match self.access_token(None) {
            Ok(token) => token,
            Err(error) => {
                self.forget()?;
                return Err(error);
            }
        };
        self.forget()?;
        self.api.logout(&token, all)
    }

    pub fn delete_account(&self) -> Result<(), AccountError> {
        let (user_id, token) = self.credentials(None, None)?;
        let result = match self.api.delete_account(&token) {
            Err(AccountError::Unauthorized) => {
                let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
                self.api.delete_account(&replacement)
            }
            result => result,
        };
        result?;
        self.forget()
    }

    fn authenticated<T, F>(&self, operation: F) -> Result<T, AccountError>
    where
        F: Fn(&A, &str) -> Result<T, AccountError>,
    {
        let (user_id, token) = self.credentials(None, None)?;
        match operation(&self.api, &token) {
            Err(AccountError::Unauthorized) => {
                let (_, replacement) = self.credentials(Some(&token), Some(&user_id))?;
                operation(&self.api, &replacement)
            }
            result => result,
        }
    }

    pub fn preference_schema(&self) -> Result<AccountPreferenceSchema, AccountError> {
        let schema = self.authenticated(|api, token| api.preference_schema(token))?;
        validate_preference_schema(&schema)?;
        Ok(schema)
    }

    pub fn preferences(&self) -> Result<AccountPreferences, AccountError> {
        let preferences = self.authenticated(|api, token| api.preferences(token))?;
        validate_account_preferences(&preferences)?;
        Ok(preferences)
    }

    pub fn put_preferences(
        &self,
        preferences: &AccountPreferences,
    ) -> Result<AccountPreferences, AccountError> {
        validate_account_preferences(preferences)?;
        let updated = self.authenticated(|api, token| api.put_preferences(preferences, token))?;
        validate_account_preferences(&updated)?;
        Ok(updated)
    }

    pub fn clipboard(&self, search: &str) -> Result<AccountClipboardPage, AccountError> {
        self.authenticated(|api, token| api.clipboard(search, token))
    }

    pub fn set_clipboard_enabled(&self, enabled: bool) -> Result<(), AccountError> {
        self.authenticated(|api, token| api.set_clipboard_enabled(enabled, token))
    }

    pub fn add_clipboard(&self, text: &str) -> Result<AccountClipboardItem, AccountError> {
        self.authenticated(|api, token| api.add_clipboard(text, token))
    }

    pub fn delete_clipboard(&self, id: Option<&str>) -> Result<(), AccountError> {
        self.authenticated(|api, token| api.delete_clipboard(id, token))
    }

    pub fn dictionary(
        &self,
        kind: DictionaryKind,
        search: &str,
        offset: usize,
    ) -> Result<AccountDictionaryPage, AccountError> {
        self.authenticated(|api, token| api.dictionary(kind, search, offset, token))
    }

    pub fn dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        offset: usize,
        scheme: &str,
        profile: &str,
    ) -> Result<AccountDictionaryCatalogPage, AccountError> {
        self.authenticated(|api, token| {
            api.dictionary_catalog(kind, code, offset, scheme, profile, token)
        })
    }

    pub fn dictionary_changes(
        &self,
        after: i64,
        limit: usize,
    ) -> Result<AccountDictionaryChangePage, AccountError> {
        self.authenticated(|api, token| api.dictionary_changes(after, limit, token))
    }

    pub fn dictionary_snapshot(&self) -> Result<Vec<u8>, AccountError> {
        self.authenticated(|api, token| api.dictionary_snapshot(token))
    }

    pub fn dictionary_snapshot_to_file(&self, destination: &Path) -> Result<u64, AccountError> {
        self.authenticated(|api, token| api.dictionary_snapshot_to_file(destination, token))
    }

    #[allow(clippy::too_many_arguments)]
    pub fn edit_dictionary_catalog(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        revision: i64,
        replacement: Option<(&str, &str, i64)>,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.authenticated(|api, token| {
            api.edit_dictionary_catalog(kind, code, word, revision, replacement, token)
        })
    }

    pub fn personal_candidates(
        &self,
        query: &AccountCandidateQuery,
    ) -> Result<AccountPersonalCandidates, AccountError> {
        self.authenticated(|api, token| api.personal_candidates(query, token))
    }

    #[allow(clippy::too_many_arguments)]
    pub fn rank_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
        mode: &str,
        linear_step: i64,
        trigger_count: i64,
        force_top: bool,
    ) -> Result<AccountRankingResult, AccountError> {
        self.authenticated(|api, token| {
            api.rank_candidate(
                query,
                code,
                word,
                revision,
                mode,
                linear_step,
                trigger_count,
                force_top,
                token,
            )
        })
    }

    pub fn remove_candidate(
        &self,
        query: &AccountCandidateQuery,
        code: &str,
        word: &str,
        revision: i64,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.authenticated(|api, token| {
            api.remove_candidate(query, code, word, revision, token)
        })
    }

    pub fn fixed_positions(
        &self,
        context: &str,
        offset: usize,
    ) -> Result<AccountFixedPositions, AccountError> {
        self.authenticated(|api, token| api.fixed_positions(context, offset, token))
    }

    pub fn set_fixed_position(
        &self,
        context: &str,
        code: &str,
        word: &str,
        position: Option<i64>,
        revision: i64,
    ) -> Result<AccountDictionaryRevision, AccountError> {
        self.authenticated(|api, token| {
            api.set_fixed_position(context, code, word, position, revision, token)
        })
    }

    pub fn add_dictionary(
        &self,
        kind: DictionaryKind,
        code: &str,
        word: &str,
        weight: i64,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.authenticated(|api, token| api.add_dictionary(kind, code, word, weight, token))
    }

    pub fn update_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        code: &str,
        word: &str,
        weight: i64,
        revision: i64,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.authenticated(|api, token| {
            api.update_dictionary(kind, id, code, word, weight, revision, token)
        })
    }

    pub fn delete_dictionary(
        &self,
        kind: DictionaryKind,
        id: &str,
        revision: i64,
    ) -> Result<AccountDictionaryChange, AccountError> {
        self.authenticated(|api, token| api.delete_dictionary(kind, id, revision, token))
    }

    pub fn import_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
        text: &str,
    ) -> Result<AccountDictionaryImportResult, AccountError> {
        self.authenticated(|api, token| api.import_dictionary(kind, format, text, token))
    }

    pub fn export_dictionary(
        &self,
        kind: DictionaryKind,
        format: &str,
    ) -> Result<AccountDictionaryExport, AccountError> {
        self.authenticated(|api, token| api.export_dictionary(kind, format, token))
    }

    pub fn forget(&self) -> Result<(), AccountError> {
        let mut state = self.lock()?;
        state.generation = state.generation.wrapping_add(1);
        state.refresh = None;
        state.saved = None;
        state.loaded = true;
        self.storage.clear()
    }

    fn update_user(&self, user: AccountUser) -> Result<(), AccountError> {
        let mut state = self.lock()?;
        self.load_locked(&mut state)?;
        let current = state.saved.as_mut().ok_or(AccountError::Cancelled)?;
        if current.tokens.user.id != user.id {
            return Err(AccountError::Cancelled);
        }
        current.tokens.user = user;
        self.storage.save(current)
    }
}

fn saved_session(tokens: AccountTokens) -> Result<SavedAccountSession, AccountError> {
    let now = unix_ms()?;
    let duration = tokens
        .expires_in
        .checked_mul(1000)
        .ok_or(AccountError::Unavailable)?;
    let expires_at_unix_ms = now.checked_add(duration).ok_or(AccountError::Unavailable)?;
    Ok(SavedAccountSession {
        tokens,
        expires_at_unix_ms,
    })
}

fn unix_ms() -> Result<u64, AccountError> {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|_| AccountError::Unavailable)?
        .as_millis();
    u64::try_from(millis).map_err(|_| AccountError::Unavailable)
}

fn refresh_deadline_ms() -> u64 {
    unix_ms()
        .unwrap_or(u64::MAX)
        .saturating_add(REFRESH_EARLY_SECONDS * 1000)
}

pub trait AccountSession {
    type Error;
    fn identity(&self) -> impl Future<Output = Result<AccountIdentity, Self::Error>> + Send;
    fn bearer_token(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
    fn refresh(&self) -> impl Future<Output = Result<String, Self::Error>> + Send;
}

impl<A: AccountApi, S: AccountSessionStorage> AccountSession for BackendAccountSession<A, S> {
    type Error = AccountError;

    async fn identity(&self) -> Result<AccountIdentity, Self::Error> {
        self.status()?
            .map(|user| AccountIdentity { user_id: user.id })
            .ok_or(AccountError::Unauthorized)
    }

    async fn bearer_token(&self) -> Result<String, Self::Error> {
        self.access_token(None)
    }

    async fn refresh(&self) -> Result<String, Self::Error> {
        let current = self.access_token(None)?;
        self.access_token(Some(&current))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use std::thread;

    fn token(byte: u8) -> String {
        std::iter::repeat_n(char::from(byte), 64).collect()
    }

    fn user() -> AccountUser {
        AccountUser {
            id: "fixture-user".into(),
            display_name: "Fixture".into(),
            created_at: "2026-01-01T00:00:00Z".into(),
        }
    }

    fn tokens(access: u8, refresh: u8, expires_in: u64) -> AccountTokens {
        AccountTokens {
            access_token: token(access),
            refresh_token: token(refresh),
            token_type: "Bearer".into(),
            expires_in,
            user: user(),
        }
    }

    #[test]
    fn validates_clipboard_boundaries() {
        let valid_id = "0123456789abcdef".repeat(4);
        assert!(validate_clipboard_id(&valid_id).is_ok());
        assert!(validate_clipboard_id(&valid_id.to_uppercase()).is_err());
        assert!(validate_clipboard_id(&format!("{valid_id}0")).is_err());

        assert!(validate_clipboard_search(&"a".repeat(1024)).is_ok());
        assert!(validate_clipboard_search(&"a".repeat(1025)).is_err());
        assert!(validate_clipboard_search("safe\u{7f}query").is_err());

        let valid_text = "😀".repeat(2000);
        assert!(validate_clipboard_text(&valid_text).is_ok());
        assert!(validate_clipboard_text(&format!("{valid_text}😀")).is_err());
        assert!(validate_clipboard_text("\n\r\t").is_err());

        let item = || AccountClipboardItem {
            id: valid_id.clone(),
            text: "fixture clipboard text".into(),
            updated_at: "2026-01-01T00:00:00Z".into(),
        };
        assert!(validate_clipboard_page(&AccountClipboardPage {
            enabled: true,
            items: vec![item(); 50],
        })
        .is_ok());
        let mut too_many = vec![item(); 50];
        too_many.push(item());
        assert!(validate_clipboard_page(&AccountClipboardPage {
            enabled: true,
            items: too_many,
        })
        .is_err());
    }

    #[test]
    fn validates_dictionary_boundaries() {
        let valid_id = "0123456789abcdef".repeat(4);
        assert_eq!(
            dictionary_path(DictionaryKind::Pinyin, 2, "ni hao").unwrap(),
            "/v1/users/me/dictionaries/pinyin?q=ni%20hao&offset=2&limit=100"
        );
        assert_eq!(
            dictionary_catalog_path(DictionaryKind::Pinyin, "nihc", 0, "shuangpin", "xiaohe")
                .unwrap(),
            "/v1/users/me/dictionaries/pinyin/catalog?q=nihc&offset=0&limit=100&scheme=shuangpin&profile=xiaohe"
        );
        assert!(dictionary_path(DictionaryKind::Wubi, 1_000_001, "").is_err());
        assert!(dictionary_catalog_path(DictionaryKind::Pinyin, "", 1_000_001, "pinyin", "x").is_err());
        assert!(validate_dictionary_catalog_query("", 0, "", "x").is_err());
        assert!(validate_dictionary_id(&valid_id).is_ok());
        assert!(validate_dictionary_id(&valid_id.to_uppercase()).is_err());

        assert!(validate_dictionary_value(DictionaryKind::Pinyin, "ni' hao", "你好", 1).is_ok());
        assert!(validate_dictionary_value(DictionaryKind::Wubi, "abcd", "字", 0).is_ok());
        assert!(validate_dictionary_value(DictionaryKind::Wubi, "abcde", "字", 0).is_err());
        assert!(
            validate_dictionary_value(DictionaryKind::Quick, "k2", &"字".repeat(199), 1).is_ok()
        );
        assert!(
            validate_dictionary_value(DictionaryKind::Quick, "k2", &"字".repeat(200), 1).is_err()
        );
        assert!(validate_dictionary_value(DictionaryKind::English, "hello", "word", 1).is_ok());
        assert!(validate_dictionary_value(DictionaryKind::English, "hello1", "word", 1).is_err());
        assert!(validate_dictionary_import(DictionaryKind::Pinyin, "hans", "你好").is_ok());
        assert!(validate_dictionary_import(DictionaryKind::Wubi, "hans", "你好").is_err());

        let entry = || AccountDictionaryEntry {
            id: valid_id.clone(),
            kind: DictionaryKind::Pinyin,
            code: "ni".into(),
            word: "你".into(),
            weight: 1,
            revision: 2,
        };
        assert!(validate_dictionary_page(
            &AccountDictionaryPage {
                entries: vec![entry(); 100],
                has_more: true,
                offset: 0,
            },
            DictionaryKind::Pinyin
        )
        .is_ok());
        assert!(validate_dictionary_page(
            &AccountDictionaryPage {
                entries: vec![entry(); 101],
                has_more: true,
                offset: 0,
            },
            DictionaryKind::Pinyin
        )
        .is_err());
        assert!(validate_dictionary_catalog_page(
            &AccountDictionaryCatalogPage {
                entries: vec![AccountDictionaryCatalogEntry {
                    kind: DictionaryKind::Pinyin,
                    code: "ni".into(),
                    word: "你".into(),
                    weight: 1,
                }],
                has_more: false,
                offset: 0,
                revision: 2,
                normalized: "ni".into(),
            },
            DictionaryKind::Pinyin
        )
        .is_ok());
    }

    #[derive(Clone, Default)]
    struct MemoryStorage(Arc<Mutex<Option<SavedAccountSession>>>);

    impl AccountSessionStorage for MemoryStorage {
        fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
            self.0
                .lock()
                .map(|value| value.clone())
                .map_err(|_| AccountError::Storage)
        }

        fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
            *self.0.lock().map_err(|_| AccountError::Storage)? = Some(session.clone());
            Ok(())
        }

        fn clear(&self) -> Result<(), AccountError> {
            *self.0.lock().map_err(|_| AccountError::Storage)? = None;
            Ok(())
        }
    }

    #[derive(Clone)]
    struct FakeApi {
        refreshes: Arc<AtomicUsize>,
        reject_refresh: Arc<AtomicBool>,
        refresh_gate: Option<Arc<(Mutex<bool>, Condvar)>>,
    }

    impl FakeApi {
        fn new() -> Self {
            Self {
                refreshes: Arc::new(AtomicUsize::new(0)),
                reject_refresh: Arc::new(AtomicBool::new(false)),
                refresh_gate: None,
            }
        }
    }

    impl AccountApi for FakeApi {
        fn providers(&self) -> Result<HashMap<String, bool>, AccountError> {
            Ok(HashMap::from([("email".into(), true)]))
        }

        fn challenge(
            &self,
            _provider: &str,
            _target: &str,
        ) -> Result<AccountChallenge, AccountError> {
            Ok(AccountChallenge {
                challenge_id: "fixture-challenge".into(),
                expires_in: 300,
                nonce: None,
                authorization_url: None,
            })
        }

        fn login(
            &self,
            _challenge: &str,
            _credential: &str,
        ) -> Result<AccountTokens, AccountError> {
            Ok(tokens(b'a', b'b', 900))
        }

        fn refresh(&self, _refresh_token: &str) -> Result<AccountTokens, AccountError> {
            self.refreshes.fetch_add(1, Ordering::SeqCst);
            if let Some(gate) = &self.refresh_gate {
                let (lock, ready) = &**gate;
                let mut open = lock.lock().map_err(|_| AccountError::Unavailable)?;
                while !*open {
                    open = ready.wait(open).map_err(|_| AccountError::Unavailable)?;
                }
            }
            if self.reject_refresh.load(Ordering::SeqCst) {
                Err(AccountError::Unauthorized)
            } else {
                Ok(tokens(b'c', b'd', 900))
            }
        }

        fn profile(&self, _access_token: &str) -> Result<AccountProfile, AccountError> {
            Ok(AccountProfile {
                user: user(),
                identities: vec![AccountProfileIdentity {
                    provider: "email".into(),
                    subject: "masked-fixture".into(),
                }],
            })
        }

        fn rename(&self, _display_name: &str, _access_token: &str) -> Result<(), AccountError> {
            Ok(())
        }

        fn logout(&self, _access_token: &str, _all: bool) -> Result<(), AccountError> {
            Ok(())
        }

        fn delete_account(&self, _access_token: &str) -> Result<(), AccountError> {
            Ok(())
        }

        fn preference_schema(
            &self,
            access_token: &str,
        ) -> Result<AccountPreferenceSchema, AccountError> {
            if access_token == token(b'a') {
                return Err(AccountError::Unauthorized);
            }
            Ok(AccountPreferenceSchema {
                fields: BTreeMap::from([
                    (
                        "input.schema".into(),
                        AccountPreferenceField {
                            value_type: "string".into(),
                        },
                    ),
                    (
                        "platform.ios.nine_key".into(),
                        AccountPreferenceField {
                            value_type: "boolean".into(),
                        },
                    ),
                ]),
                maximum_bytes: 65_536,
                update_mode: "replace".into(),
                revision_required: true,
            })
        }

        fn preferences(&self, access_token: &str) -> Result<AccountPreferences, AccountError> {
            if access_token == token(b'a') {
                return Err(AccountError::Unauthorized);
            }
            Ok(AccountPreferences {
                revision: 42,
                settings: BTreeMap::from([
                    (
                        "input.schema".into(),
                        AccountPreferenceValue::String("quanpin".into()),
                    ),
                    (
                        "platform.ios.nine_key".into(),
                        AccountPreferenceValue::Boolean(true),
                    ),
                ]),
            })
        }

        fn put_preferences(
            &self,
            preferences: &AccountPreferences,
            access_token: &str,
        ) -> Result<AccountPreferences, AccountError> {
            if access_token == token(b'a') {
                return Err(AccountError::Unauthorized);
            }
            Ok(AccountPreferences {
                revision: preferences.revision + 1,
                settings: preferences.settings.clone(),
            })
        }
    }

    fn installed(storage: &MemoryStorage, expires_at_unix_ms: u64) {
        *storage.0.lock().unwrap() = Some(SavedAccountSession {
            tokens: tokens(b'a', b'b', 900),
            expires_at_unix_ms,
        });
    }

    #[test]
    fn validates_public_inputs_and_tokens() {
        assert!(validate_identity(&AccountIdentity {
            user_id: "user-1".into()
        })
        .is_ok());
        assert!(validate_identity(&AccountIdentity {
            user_id: "bad\n".into()
        })
        .is_err());
        assert_eq!(
            validate_provider_target("email", " fixture@example.test"),
            Err(AccountError::Invalid)
        );
        assert_eq!(
            validate_login("challenge", "１２３４５６"),
            Err(AccountError::Invalid)
        );
        let mut invalid = tokens(b'a', b'b', 900);
        invalid.access_token = token(b'A');
        assert_eq!(validate_tokens(&invalid), Err(AccountError::Unavailable));
    }

    #[test]
    fn account_preferences_validate_and_merge_preserves_other_platforms() {
        let base = AccountPreferences {
            revision: 42,
            settings: BTreeMap::from([
                (
                    "input.schema".into(),
                    AccountPreferenceValue::String("quanpin".into()),
                ),
                (
                    "platform.ios.nine_key".into(),
                    AccountPreferenceValue::Boolean(true),
                ),
            ]),
        };
        let schema = AccountPreferenceSchema {
            fields: BTreeMap::from([
                (
                    "input.schema".into(),
                    AccountPreferenceField {
                        value_type: "string".into(),
                    },
                ),
                (
                    "platform.android.nine_key".into(),
                    AccountPreferenceField {
                        value_type: "boolean".into(),
                    },
                ),
            ]),
            maximum_bytes: 65_536,
            update_mode: "replace".into(),
            revision_required: true,
        };
        let replacing = BTreeMap::from([
            (
                "input.schema".into(),
                AccountPreferenceValue::String("shuangpin".into()),
            ),
            (
                "platform.android.nine_key".into(),
                AccountPreferenceValue::Boolean(false),
            ),
        ]);
        let merged = merge_account_preferences(&base, &replacing, &schema).unwrap();
        assert_eq!(merged.revision, 42);
        assert_eq!(
            merged.settings["input.schema"],
            AccountPreferenceValue::String("shuangpin".into())
        );
        assert_eq!(
            merged.settings["platform.ios.nine_key"],
            AccountPreferenceValue::Boolean(true)
        );
        assert_eq!(
            merged.settings["platform.android.nine_key"],
            AccountPreferenceValue::Boolean(false)
        );
        assert_eq!(
            merge_account_preferences(
                &base,
                &BTreeMap::from([(
                    "input.schema".into(),
                    AccountPreferenceValue::Boolean(true),
                )]),
                &schema
            ),
            Err(AccountError::Invalid)
        );
    }

    #[test]
    fn account_preferences_refresh_after_unauthorized_and_preserve_revision_conflicts() {
        let storage = MemoryStorage::default();
        installed(&storage, u64::MAX);
        let api = FakeApi::new();
        let refreshes = Arc::clone(&api.refreshes);
        let session = BackendAccountSession::new(api, storage);
        let schema = session.preference_schema().unwrap();
        assert!(schema.fields.contains_key("input.schema"));
        let cloud = session.preferences().unwrap();
        assert_eq!(cloud.revision, 42);
        let updated = session
            .put_preferences(&cloud)
            .expect("refresh should make the write succeed");
        assert_eq!(updated.revision, 43);
        assert_eq!(refreshes.load(Ordering::SeqCst), 1);
        assert_eq!(AccountError::from_status(StatusCode::CONFLICT), AccountError::Conflict);
        assert_eq!(AccountError::Conflict.code(), "account_conflict");
    }

    #[test]
    fn refreshes_once_for_concurrent_callers() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let mut api = FakeApi::new();
        api.refresh_gate = Some(Arc::clone(&gate));
        let count = Arc::clone(&api.refreshes);
        let session = Arc::new(BackendAccountSession::new(api, storage));
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let session = Arc::clone(&session);
                thread::spawn(move || session.access_token(None))
            })
            .collect();
        while count.load(Ordering::SeqCst) == 0 {
            thread::yield_now();
        }
        let (lock, ready) = &*gate;
        *lock.lock().unwrap() = true;
        ready.notify_all();
        let values: Vec<_> = handles
            .into_iter()
            .map(|handle| handle.join().unwrap().unwrap())
            .collect();
        assert_eq!(count.load(Ordering::SeqCst), 1);
        assert!(values.iter().all(|value| value == &token(b'c')));
    }

    #[test]
    fn unauthorized_refresh_clears_storage() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let api = FakeApi::new();
        api.reject_refresh.store(true, Ordering::SeqCst);
        let session = BackendAccountSession::new(api, storage.clone());
        assert_eq!(session.access_token(None), Err(AccountError::Unauthorized));
        assert!(storage.load().unwrap().is_none());
        assert_eq!(session.status().unwrap(), None);
    }

    #[test]
    fn late_refresh_cannot_restore_forgotten_session() {
        let storage = MemoryStorage::default();
        installed(&storage, 0);
        let gate = Arc::new((Mutex::new(false), Condvar::new()));
        let mut api = FakeApi::new();
        api.refresh_gate = Some(Arc::clone(&gate));
        let count = Arc::clone(&api.refreshes);
        let session = Arc::new(BackendAccountSession::new(api, storage.clone()));
        let worker = {
            let session = Arc::clone(&session);
            thread::spawn(move || session.access_token(None))
        };
        while count.load(Ordering::SeqCst) == 0 {
            thread::yield_now();
        }
        session.forget().unwrap();
        let (lock, ready) = &*gate;
        *lock.lock().unwrap() = true;
        ready.notify_all();
        assert_eq!(worker.join().unwrap(), Err(AccountError::Cancelled));
        assert!(storage.load().unwrap().is_none());
    }

    #[test]
    fn logout_clears_local_session_before_remote_result() {
        let storage = MemoryStorage::default();
        installed(&storage, u64::MAX);
        let session = BackendAccountSession::new(FakeApi::new(), storage.clone());
        session.logout(true).unwrap();
        assert!(storage.load().unwrap().is_none());
        assert_eq!(session.status().unwrap(), None);
    }

    fn serve_once(response: Vec<u8>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut request = [0_u8; 4096];
            let _ = stream.read(&mut request);
            std::io::Write::write_all(&mut stream, &response).unwrap();
        });
        format!("http://{address}")
    }

    #[test]
    fn transport_rejects_redirects() {
        let origin = serve_once(
            b"HTTP/1.1 302 Found\r\nLocation: https://example.test/\r\nContent-Length: 0\r\n\r\n"
                .to_vec(),
        );
        let client = BackendAccountClient::loopback(&origin).unwrap();
        assert_eq!(client.providers(), Err(AccountError::Unavailable));
    }

    #[test]
    fn transport_rejects_oversized_responses() {
        let body = vec![b'x'; MAX_JSON_BYTES + 1];
        let header = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n",
            body.len()
        );
        let mut response = header.into_bytes();
        response.extend(body);
        let origin = serve_once(response);
        let client = BackendAccountClient::loopback(&origin).unwrap();
        assert_eq!(client.providers(), Err(AccountError::Unavailable));
    }

    #[test]
    fn account_dictionary_transport_maps_flattened_responses() {
        let id = "0123456789abcdef".repeat(4);
        let page_body = serde_json::json!({
            "entries": [{
                "id": id,
                "kind": "pinyin",
                "code": "ni",
                "word": "fixture",
                "weight": 1,
                "revision": 2
            }],
            "has_more": false,
            "offset": 0
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            page_body.len(),
            page_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let page = client
            .dictionary(DictionaryKind::Pinyin, "fixture", 0, &token(b'a'))
            .unwrap();
        assert_eq!(page.entries[0].word, "fixture");
        assert_eq!(page.entries[0].revision, 2);

        let change_body = serde_json::json!({
            "revision": 3,
            "previous": null,
            "replacement": {
                "id": "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210",
                "kind": "pinyin",
                "code": "ni",
                "word": "fixture",
                "weight": 1,
                "revision": 3
            }
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            change_body.len(),
            change_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let change = client
            .add_dictionary(DictionaryKind::Pinyin, "ni", "fixture", 1, &token(b'a'))
            .unwrap();
        assert_eq!(change.revision, 3);
        assert_eq!(change.replacement.unwrap().id.len(), 64);

        let export = b"ni\tfixture\t1\n".to_vec();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: text/plain\r\n\r\n",
            export.len()
        )
        .into_bytes()
        .into_iter()
        .chain(export)
        .collect();
        let client = BackendAccountClient::loopback(&serve_once(response)).unwrap();
        let exported = client
            .export_dictionary(DictionaryKind::Pinyin, "standard", &token(b'a'))
            .unwrap();
        assert_eq!(exported.text, "ni\tfixture\t1\n");
        assert_eq!(exported.filename, "dictionary-pinyin.tsv");

        let catalog_body = serde_json::json!({
            "entries": [{
                "kind": "pinyin",
                "code": "ni'hao",
                "word": "你好",
                "weight": 100000
            }],
            "offset": 0,
            "has_more": false,
            "revision": 42,
            "normalized": "ni'hao"
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            catalog_body.len(),
            catalog_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let catalog = client
            .dictionary_catalog(
                DictionaryKind::Pinyin,
                "nihc",
                0,
                "shuangpin",
                "xiaohe",
                &token(b'a'),
            )
            .unwrap();
        assert_eq!(catalog.revision, 42);
        assert_eq!(catalog.normalized, "ni'hao");

        let change_body = serde_json::json!({
            "revision": 43,
            "previous": null,
            "replacement": null
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            change_body.len(),
            change_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let change = client
            .edit_dictionary_catalog(
                DictionaryKind::Pinyin,
                "ni",
                "你",
                42,
                None,
                &token(b'a'),
            )
            .unwrap();
        assert_eq!(change.revision, 43);

        let changes_body = serde_json::json!({
            "changes": [{
                "revision": 44,
                "previous": null,
                "replacement": null
            }],
            "next": 44,
            "has_more": false
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            changes_body.len(),
            changes_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let changes = client.dictionary_changes(43, 1, &token(b'a')).unwrap();
        assert_eq!(changes.next, 44);
        assert!(!changes.has_more);

        let snapshot = b"{\"type\":\"header\"}\n".to_vec();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/x-ndjson\r\n\r\n",
            snapshot.len()
        )
        .into_bytes()
        .into_iter()
        .chain(snapshot)
        .collect();
        let client = BackendAccountClient::loopback(&serve_once(response)).unwrap();
        assert_eq!(
            client.dictionary_snapshot(&token(b'a')).unwrap(),
            b"{\"type\":\"header\"}\n"
        );

        let snapshot = b"streamed snapshot\n".to_vec();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/x-ndjson\r\n\r\n",
            snapshot.len()
        )
        .into_bytes()
        .into_iter()
        .chain(snapshot.clone())
        .collect();
        let client = BackendAccountClient::loopback(&serve_once(response)).unwrap();
        let directory = tempfile::tempdir().unwrap();
        let destination = directory.path().join("snapshot.ndjson");
        let size = client
            .dictionary_snapshot_to_file(&destination, &token(b'a'))
            .unwrap();
        assert_eq!(size, snapshot.len() as u64);
        assert_eq!(std::fs::read(destination).unwrap(), snapshot);

        let invalid_changes = serde_json::json!({
            "changes": [{"revision": 44, "previous": null, "replacement": null}],
            "next": 43,
            "has_more": false
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            invalid_changes.len(),
            invalid_changes
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        assert_eq!(
            client.dictionary_changes(43, 1, &token(b'a')),
            Err(AccountError::Unavailable)
        );
        assert_eq!(
            client.dictionary_changes(-1, 1, &token(b'a')),
            Err(AccountError::Invalid)
        );
    }

    #[test]
    fn validates_candidate_transport_boundaries() {
        let query = AccountCandidateQuery {
            text: "nihc".into(),
            kind: "pinyin".into(),
            scheme: "shuangpin".into(),
            profile: "xiaohe".into(),
            limit: 100,
        };
        assert!(validate_candidate_query(&query).is_ok());
        assert!(validate_candidate_query(&AccountCandidateQuery {
            text: "".into(),
            ..query.clone()
        })
        .is_err());
        assert!(validate_ranking_arguments(&query, 42, "pin", 1, 1).is_ok());
        assert!(validate_ranking_arguments(&AccountCandidateQuery {
            kind: "quick".into(),
            ..query.clone()
        }, 42, "pin", 1, 1)
        .is_err());
        assert!(validate_candidate_value(&query, "nihc", "你好").is_ok());
        assert!(validate_candidate_value(&query, "", "你好").is_err());
    }

    #[test]
    fn account_candidate_transport_maps_canonical_and_fixed_state() {
        let candidate_body = serde_json::json!({
            "candidates": [{
                "code": "nihc",
                "word": "你好",
                "weight": 10,
                "canonical_pinyin": "ni'hao"
            }],
            "context": "server:context",
            "revision": 42
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            candidate_body.len(),
            candidate_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let query = AccountCandidateQuery {
            text: "nihc".into(),
            kind: "pinyin".into(),
            scheme: "shuangpin".into(),
            profile: "xiaohe".into(),
            limit: 100,
        };
        let candidates = client
            .personal_candidates(&query, &token(b'a'))
            .unwrap();
        assert_eq!(candidates.candidates[0].mutation_code(), "ni'hao");

        let ranking_body = serde_json::json!({
            "revision": 43,
            "changed": true,
            "selection": { "count": 0 }
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            ranking_body.len(),
            ranking_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let ranking = client
            .rank_candidate(
                &query,
                "ni'hao",
                "你好",
                42,
                "pin",
                1,
                1,
                false,
                &token(b'a'),
            )
            .unwrap();
        assert!(ranking.changed);
        assert_eq!(ranking.revision, 43);

        let positions_body = serde_json::json!({
            "positions": [{
                "context": "server:context",
                "code": "ni'hao",
                "word": "你好",
                "position": 1
            }],
            "offset": 0,
            "has_more": false
        })
        .to_string();
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            positions_body.len(),
            positions_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let positions = client
            .fixed_positions("server:context", 0, &token(b'a'))
            .unwrap();
        assert_eq!(positions.positions[0].position, 1);

        let revision_body = r#"{"revision":44}"#;
        let response = format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nContent-Type: application/json\r\n\r\n{}",
            revision_body.len(),
            revision_body
        );
        let client = BackendAccountClient::loopback(&serve_once(response.into_bytes())).unwrap();
        let revision = client
            .set_fixed_position("server:context", "ni'hao", "你好", None, 43, &token(b'a'))
            .unwrap();
        assert_eq!(revision.revision, 44);
    }
}

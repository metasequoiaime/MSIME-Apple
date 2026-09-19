//! Cross-process queue for personal dictionary edits.
//!
//! The Engine remains the authority for entry validation and dictionary data. This
//! module only owns the small host/keyboard hand-off file, which is shared by the
//! Android settings process and the `:ime` process.

use crate::file_lock;
use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use uuid::Uuid;

const MAX_STATE_BYTES: usize = 8 * 1024 * 1024;
const MAX_REQUESTS: usize = 160;
const MAX_ACTIVE_REQUESTS: usize = 128;
const MAX_PAGE_ENTRIES: usize = 100;
const MAX_HISTORY: usize = 32;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash, Serialize, Deserialize)]
pub enum PersonalWordKind {
    #[serde(rename = "pinyin")]
    Pinyin,
    #[serde(rename = "wubi")]
    Wubi,
    #[serde(rename = "quickPhrase")]
    QuickPhrase,
    #[serde(rename = "english")]
    English,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct PersonalWord {
    pub kind: PersonalWordKind,
    pub key: String,
    pub value: String,
    pub weight: i64,
}

impl PersonalWord {
    /// The identity deliberately includes a length prefix so arbitrary phrase
    /// text cannot collide with a key separator.
    pub fn identity(&self) -> String {
        format!(
            "{}:{}:{}{}",
            match self.kind {
                PersonalWordKind::Pinyin => "pinyin",
                PersonalWordKind::Wubi => "wubi",
                PersonalWordKind::QuickPhrase => "quickPhrase",
                PersonalWordKind::English => "english",
            },
            self.key.len(),
            self.key,
            self.value
        )
    }

    /// This is transport validation only. The Engine still validates and
    /// normalizes entries before applying them.
    pub fn validate(&self) -> Result<(), &'static str> {
        let key_limit = match self.kind {
            PersonalWordKind::Pinyin => 256,
            PersonalWordKind::Wubi => 4,
            PersonalWordKind::QuickPhrase => 32,
            PersonalWordKind::English => 64,
        };
        let key_valid = match self.kind {
            PersonalWordKind::Pinyin => self
                .key
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte == b'\'' || byte == b' '),
            PersonalWordKind::Wubi | PersonalWordKind::QuickPhrase => {
                self.key.bytes().all(|byte| {
                    byte.is_ascii_lowercase()
                        || (self.kind == PersonalWordKind::QuickPhrase && byte.is_ascii_digit())
                })
            }
            PersonalWordKind::English => self.key.bytes().all(|byte| byte.is_ascii_alphabetic()),
        };
        if self.key.is_empty()
            || self.key.len() > key_limit
            || !key_valid
            || self.value.is_empty()
            || self.value.chars().any(char::is_control)
            || self.weight < 0
        {
            return Err("invalid personal dictionary entry");
        }
        if self.kind == PersonalWordKind::QuickPhrase && self.value.encode_utf16().count() > 199 {
            return Err("personal quick phrase is too long");
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum PersonalWordRequestStatus {
    Pending,
    Applied,
    Failed,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersonalWordRequest {
    pub id: String,
    pub previous: Option<PersonalWord>,
    pub replacement: Option<PersonalWord>,
    pub status: PersonalWordRequestStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub created_at: Option<String>,
}

impl PersonalWordRequest {
    fn identities(&self) -> impl Iterator<Item = String> + '_ {
        [self.previous.as_ref(), self.replacement.as_ref()]
            .into_iter()
            .flatten()
            .map(PersonalWord::identity)
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PersonalDictionaryState {
    pub version: u32,
    pub requests: Vec<PersonalWordRequest>,
    pub entries: Vec<PersonalWord>,
    pub has_more: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snapshot_date: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snapshot_error: Option<String>,
    pub page_offset: usize,
    pub requested_page_offset: usize,
    pub refresh_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub completed_refresh_id: Option<String>,
}

impl Default for PersonalDictionaryState {
    fn default() -> Self {
        Self {
            version: 1,
            requests: Vec::new(),
            entries: Vec::new(),
            has_more: false,
            snapshot_date: None,
            snapshot_error: None,
            page_offset: 0,
            requested_page_offset: 0,
            refresh_id: Uuid::new_v4().to_string(),
            completed_refresh_id: None,
        }
    }
}

impl PersonalDictionaryState {
    pub fn pending_count(&self) -> usize {
        self.requests
            .iter()
            .filter(|request| request.status == PersonalWordRequestStatus::Pending)
            .count()
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct PersonalWordPage {
    pub entries: Vec<PersonalWord>,
    pub has_more: bool,
}

#[derive(Debug, thiserror::Error)]
pub enum PersonalDictionaryError {
    #[error("personal dictionary shared directory is unavailable")]
    Unavailable,
    #[error("personal dictionary state is invalid; the existing file was preserved")]
    InvalidState,
    #[error("personal dictionary is busy")]
    Busy,
    #[error("too many personal dictionary requests are waiting")]
    TooManyRequests,
    #[error("a personal dictionary entry already has a waiting request")]
    Conflict,
    #[error("personal dictionary request is invalid")]
    InvalidRequest,
    #[error("personal dictionary I/O failed")]
    Io(#[source] io::Error),
}

impl From<io::Error> for PersonalDictionaryError {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

/// A lock-protected state file shared by host UI and keyboard processes.
pub struct PersonalDictionaryStore {
    directory: PathBuf,
}

impl PersonalDictionaryStore {
    pub fn new(directory: impl AsRef<Path>) -> Self {
        Self {
            directory: directory.as_ref().to_owned(),
        }
    }

    pub fn directory(&self) -> &Path {
        &self.directory
    }

    pub fn read(&self) -> Result<PersonalDictionaryState, PersonalDictionaryError> {
        let file = self.directory.join("sync.json");
        if !file.exists() {
            return Ok(PersonalDictionaryState::default());
        }
        read_file(&file)
    }

    pub fn enqueue(
        &self,
        previous: Option<PersonalWord>,
        replacement: Option<PersonalWord>,
        id: String,
    ) -> Result<(), PersonalDictionaryError> {
        let request = PersonalWordRequest {
            id,
            previous,
            replacement,
            status: PersonalWordRequestStatus::Pending,
            error: None,
            created_at: None,
        };
        if request.previous.is_none() && request.replacement.is_none() {
            return Err(PersonalDictionaryError::InvalidRequest);
        }
        validate_request_id(&request.id)?;
        for word in request.previous.iter().chain(request.replacement.iter()) {
            word.validate()
                .map_err(|_| PersonalDictionaryError::InvalidRequest)?;
        }
        self.update(|state| enqueue_request(state, request))
    }

    pub fn enqueue_import(
        &self,
        words: Vec<PersonalWord>,
        id_prefix: String,
    ) -> Result<(), PersonalDictionaryError> {
        if words.is_empty() || words.len() > MAX_ACTIVE_REQUESTS || id_prefix.is_empty() {
            return Err(PersonalDictionaryError::InvalidRequest);
        }
        validate_request_id(&id_prefix)?;
        let mut identities = std::collections::HashSet::new();
        for word in &words {
            word.validate()
                .map_err(|_| PersonalDictionaryError::InvalidRequest)?;
            if !identities.insert(word.identity()) {
                return Err(PersonalDictionaryError::InvalidRequest);
            }
        }
        self.update(|state| {
            let active = state
                .requests
                .iter()
                .filter(|request| request.status != PersonalWordRequestStatus::Applied)
                .count();
            if active + words.len() > MAX_ACTIVE_REQUESTS {
                return Err(PersonalDictionaryError::TooManyRequests);
            }
            if state.requests.iter().any(|request| {
                request.status != PersonalWordRequestStatus::Applied
                    && request
                        .identities()
                        .any(|identity| identities.contains(&identity))
            }) {
                return Err(PersonalDictionaryError::Conflict);
            }
            prune_history(state);
            for (index, word) in words.iter().cloned().enumerate() {
                state.requests.push(PersonalWordRequest {
                    id: format!("{id_prefix}-{index}"),
                    previous: None,
                    replacement: Some(word),
                    status: PersonalWordRequestStatus::Pending,
                    error: None,
                    created_at: None,
                });
            }
            state.refresh_id = Uuid::new_v4().to_string();
            Ok(())
        })
    }

    pub fn retry(&self, id: &str) -> Result<(), PersonalDictionaryError> {
        self.update(|state| {
            let Some(index) = state.requests.iter().position(|request| {
                request.id == id && request.status == PersonalWordRequestStatus::Failed
            }) else {
                return Ok(());
            };
            let identities: std::collections::HashSet<_> =
                state.requests[index].identities().collect();
            if state.requests.iter().any(|request| {
                request.status == PersonalWordRequestStatus::Pending
                    && request
                        .identities()
                        .any(|identity| identities.contains(&identity))
            }) {
                return Err(PersonalDictionaryError::Conflict);
            }
            state.requests[index].status = PersonalWordRequestStatus::Pending;
            state.requests[index].error = None;
            state.refresh_id = Uuid::new_v4().to_string();
            Ok(())
        })
    }

    pub fn dismiss_failure(&self, id: &str) -> Result<(), PersonalDictionaryError> {
        self.update(|state| {
            state.requests.retain(|request| {
                !(request.id == id && request.status == PersonalWordRequestStatus::Failed)
            });
            Ok(())
        })
    }

    pub fn request_page(&self, offset: usize) -> Result<(), PersonalDictionaryError> {
        if offset > 1_000_000 {
            return Err(PersonalDictionaryError::InvalidRequest);
        }
        self.update(|state| {
            state.requested_page_offset = offset;
            state.refresh_id = Uuid::new_v4().to_string();
            Ok(())
        })
    }

    /// Apply at most four pending requests and refresh the confirmed page while
    /// the queue lock is held. A failed request remains independently retryable.
    pub fn synchronize<Apply, Page>(
        &self,
        mut apply: Apply,
        mut page: Page,
    ) -> Result<(), PersonalDictionaryError>
    where
        Apply: FnMut(&PersonalWordRequest) -> Result<(), String>,
        Page: FnMut(usize) -> Result<PersonalWordPage, String>,
    {
        self.update(|state| {
            let pending: Vec<usize> = state
                .requests
                .iter()
                .enumerate()
                .filter_map(|(index, request)| {
                    (request.status == PersonalWordRequestStatus::Pending).then_some(index)
                })
                .take(4)
                .collect();
            for index in pending {
                match apply(&state.requests[index]) {
                    Ok(()) => {
                        state.requests[index].status = PersonalWordRequestStatus::Applied;
                        state.requests[index].error = None;
                    }
                    Err(error) => {
                        state.requests[index].status = PersonalWordRequestStatus::Failed;
                        state.requests[index].error = Some(error.chars().take(500).collect());
                    }
                }
            }
            if state.pending_count() == 0 {
                state.completed_refresh_id = Some(state.refresh_id.clone());
            }
            match page(state.requested_page_offset) {
                Ok(snapshot) if snapshot.entries.len() <= MAX_PAGE_ENTRIES => {
                    state.entries = snapshot.entries;
                    state.has_more = snapshot.has_more;
                    state.page_offset = state.requested_page_offset;
                    state.snapshot_date = Some("updated".to_owned());
                    state.snapshot_error = None;
                }
                Ok(_) => {
                    state.snapshot_error = Some("personal dictionary page is too large".into())
                }
                Err(error) => state.snapshot_error = Some(error.chars().take(500).collect()),
            }
            Ok(())
        })
    }

    fn update<F>(&self, action: F) -> Result<(), PersonalDictionaryError>
    where
        F: FnOnce(&mut PersonalDictionaryState) -> Result<(), PersonalDictionaryError>,
    {
        fs::create_dir_all(&self.directory)?;
        let lock_path = self.directory.join("sync.lock");
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)?;
        if !file_lock::try_exclusive(&lock)? {
            return Err(PersonalDictionaryError::Busy);
        }
        let file = self.directory.join("sync.json");
        let mut state = if file.exists() {
            read_file(&file)?
        } else {
            PersonalDictionaryState::default()
        };
        validate_state(&state)?;
        action(&mut state)?;
        validate_state(&state)?;
        let bytes =
            serde_json::to_vec(&state).map_err(|_| PersonalDictionaryError::InvalidState)?;
        if bytes.len() > MAX_STATE_BYTES {
            return Err(PersonalDictionaryError::InvalidState);
        }
        let temporary = self
            .directory
            .join(format!("sync.json.tmp-{}", std::process::id()));
        let mut output = File::create(&temporary)?;
        output.write_all(&bytes)?;
        output.sync_all()?;
        fs::rename(temporary, file)?;
        Ok(())
    }
}

fn enqueue_request(
    state: &mut PersonalDictionaryState,
    request: PersonalWordRequest,
) -> Result<(), PersonalDictionaryError> {
    let active = state
        .requests
        .iter()
        .filter(|item| item.status != PersonalWordRequestStatus::Applied)
        .count();
    if active >= MAX_ACTIVE_REQUESTS {
        return Err(PersonalDictionaryError::TooManyRequests);
    }
    let identities: std::collections::HashSet<_> = request.identities().collect();
    if state.requests.iter().any(|item| {
        item.status == PersonalWordRequestStatus::Pending
            && item
                .identities()
                .any(|identity| identities.contains(&identity))
    }) {
        return Err(PersonalDictionaryError::Conflict);
    }
    prune_history(state);
    state.requests.push(request);
    state.refresh_id = Uuid::new_v4().to_string();
    Ok(())
}

fn prune_history(state: &mut PersonalDictionaryState) {
    let keep: std::collections::HashSet<_> = state
        .requests
        .iter()
        .filter(|request| request.status == PersonalWordRequestStatus::Applied)
        .rev()
        .take(MAX_HISTORY)
        .map(|request| request.id.clone())
        .collect();
    state.requests.retain(|request| {
        request.status != PersonalWordRequestStatus::Applied || keep.contains(&request.id)
    });
}

fn validate_request_id(id: &str) -> Result<(), PersonalDictionaryError> {
    if id.is_empty()
        || id.len() > 120
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
    {
        return Err(PersonalDictionaryError::InvalidRequest);
    }
    Ok(())
}

fn read_file(file: &Path) -> Result<PersonalDictionaryState, PersonalDictionaryError> {
    let metadata = fs::metadata(file)?;
    if metadata.len() as usize > MAX_STATE_BYTES {
        return Err(PersonalDictionaryError::InvalidState);
    }
    let bytes = fs::read(file)?;
    let state: PersonalDictionaryState =
        serde_json::from_slice(&bytes).map_err(|_| PersonalDictionaryError::InvalidState)?;
    validate_state(&state)?;
    Ok(state)
}

fn validate_state(state: &PersonalDictionaryState) -> Result<(), PersonalDictionaryError> {
    if state.version != 1
        || state.requests.len() > MAX_REQUESTS
        || state.entries.len() > MAX_PAGE_ENTRIES
        || state.page_offset > 1_000_000
        || state.requested_page_offset > 1_000_000
        || state.refresh_id.is_empty()
    {
        return Err(PersonalDictionaryError::InvalidState);
    }
    let mut ids = std::collections::HashSet::new();
    for request in &state.requests {
        if request.id.is_empty() || !ids.insert(&request.id) {
            return Err(PersonalDictionaryError::InvalidState);
        }
        if request.previous.is_none() && request.replacement.is_none() {
            return Err(PersonalDictionaryError::InvalidState);
        }
        if request
            .previous
            .iter()
            .chain(request.replacement.iter())
            .any(|word| word.validate().is_err())
        {
            return Err(PersonalDictionaryError::InvalidState);
        }
    }
    for word in &state.entries {
        if word.validate().is_err() {
            return Err(PersonalDictionaryError::InvalidState);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn word(key: &str, value: &str) -> PersonalWord {
        PersonalWord {
            kind: PersonalWordKind::QuickPhrase,
            key: key.into(),
            value: value.into(),
            weight: 100_000,
        }
    }

    #[test]
    fn queues_applies_failures_and_pages_without_reapplying_receipts() {
        let root = tempfile::tempdir().unwrap();
        let store = PersonalDictionaryStore::new(root.path());
        let entry = word("fixture", "测试短语");
        store
            .enqueue(None, Some(entry.clone()), "request-1".into())
            .unwrap();
        assert_eq!(store.read().unwrap().pending_count(), 1);
        let mut applied = Vec::new();
        store
            .synchronize(
                |request| {
                    applied.push(request.id.clone());
                    Ok(())
                },
                |_| {
                    Ok(PersonalWordPage {
                        entries: vec![entry.clone()],
                        has_more: true,
                    })
                },
            )
            .unwrap();
        assert_eq!(applied, ["request-1"]);
        assert_eq!(store.read().unwrap().pending_count(), 0);
        store
            .synchronize(
                |_| panic!("applied request was repeated"),
                |_| Err("page unavailable".into()),
            )
            .unwrap();
        let state = store.read().unwrap();
        assert_eq!(state.entries, vec![entry]);
        assert!(state.snapshot_error.is_some());
    }

    #[test]
    fn import_validation_and_conflicts_are_atomic() {
        let root = tempfile::tempdir().unwrap();
        let store = PersonalDictionaryStore::new(root.path());
        let first = word("one", "一");
        let second = word("two", "二");
        store
            .enqueue_import(vec![first.clone(), second.clone()], "import".into())
            .unwrap();
        let original = fs::read(root.path().join("sync.json")).unwrap();
        assert!(matches!(
            store.enqueue_import(vec![first, word("three", "三")], "second".into()),
            Err(PersonalDictionaryError::Conflict)
        ));
        assert_eq!(fs::read(root.path().join("sync.json")).unwrap(), original);
        assert_eq!(store.read().unwrap().requests.len(), 2);
    }

    #[test]
    fn malformed_state_is_rejected_without_being_overwritten() {
        let root = tempfile::tempdir().unwrap();
        let directory = root.path();
        fs::write(directory.join("sync.json"), b"not-json").unwrap();
        let store = PersonalDictionaryStore::new(directory);
        assert!(matches!(
            store.read(),
            Err(PersonalDictionaryError::InvalidState)
        ));
        assert_eq!(fs::read(directory.join("sync.json")).unwrap(), b"not-json");
    }
}

use msime_client_core::account::{
    merge_account_preferences, validate_account_preferences, AccountCandidateQuery,
    AccountChallenge, AccountChatMessage, AccountChatModels, AccountError, AccountPreferenceSchema,
    AccountPreferenceValue, AccountPreferences, AccountProfile, AccountSessionStorage, AccountUser,
    BackendAccountClient, BackendAccountSession, SavedAccountSession,
};
use msime_client_core::ai_skin::{AiSkinError, AiSkinProposal, BackendAiSkinService};
use msime_client_core::cloud_dictionary::DictionaryKind;
use msime_client_core::community_resource::{
    BackendCommunityResourceService, CommunityResource, CommunityResourceApplication,
    CommunityResourceContent, CommunityResourceKind, CommunityResourcePage,
    CommunityResourcePublication, CommunityResourceScope,
};
use msime_client_core::community_resource_library::{
    CommunityResourceLibraryError, CommunityResourceLibraryStore,
};
use msime_client_core::community_skin::{
    BackendCommunitySkinService, CommunitySkin, CommunitySkinPage,
};
use msime_client_core::custom_skin_library::{
    CustomSkinLibraryError, CustomSkinLibraryStore, SavedTouchKeyboardSkin,
};
use msime_client_core::keyboard_skin_trial::{
    KeyboardSkinTrial, KeyboardSkinTrialError, KeyboardSkinTrialStore,
};
use msime_client_core::preferences::{
    InputScheme, Preferences, PreferencesSnapshot, PreferencesStore, ShuangpinProfile, ThemeMode,
    TouchKeyboardLayout, TouchKeyboardSkin, TouchKeyboardSkinDesign,
};
use serde::de::{DeserializeSeed, MapAccess, Visitor};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use tauri::plugin::{Builder, PluginHandle, TauriPlugin};
use tauri::{Emitter, Manager, Runtime, State, Wry};
use uuid::Uuid;

const MAX_SECURE_SESSION_BYTES: usize = 16 * 1024;

#[derive(Deserialize)]
struct LoadResponse {
    value: Option<String>,
}

#[derive(Serialize)]
struct SaveRequest<'a> {
    value: &'a str,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct FeedbackSettings {
    sound_enabled: bool,
    haptics_enabled: bool,
    haptic_strength: String,
}

#[derive(Serialize)]
struct AiModelsRequest<'a> {
    endpoint: &'a str,
    token: &'a str,
}

#[derive(Serialize)]
struct AiTestRequest<'a> {
    endpoint: &'a str,
    model: &'a str,
    prompt: &'a str,
    token: &'a str,
    text: &'a str,
}

#[derive(Clone)]
struct AndroidAccountStorage<R: Runtime>(PluginHandle<R>);

impl<R: Runtime> AccountSessionStorage for AndroidAccountStorage<R> {
    fn load(&self) -> Result<Option<SavedAccountSession>, AccountError> {
        let response = self
            .0
            .run_mobile_plugin::<LoadResponse>("loadSession", ())
            .map_err(|_| AccountError::Storage)?;
        response
            .value
            .map(|value| {
                if value.is_empty() || value.len() > MAX_SECURE_SESSION_BYTES {
                    return Err(AccountError::Storage);
                }
                serde_json::from_str(&value).map_err(|_| AccountError::Storage)
            })
            .transpose()
    }

    fn save(&self, session: &SavedAccountSession) -> Result<(), AccountError> {
        let value = serde_json::to_string(session).map_err(|_| AccountError::Storage)?;
        if value.is_empty() || value.len() > MAX_SECURE_SESSION_BYTES {
            return Err(AccountError::Storage);
        }
        self.0
            .run_mobile_plugin::<()>("saveSession", SaveRequest { value: &value })
            .map_err(|_| AccountError::Storage)
    }

    fn clear(&self) -> Result<(), AccountError> {
        self.0
            .run_mobile_plugin::<()>("clearSession", ())
            .map_err(|_| AccountError::Storage)
    }
}

type Session = BackendAccountSession<BackendAccountClient, AndroidAccountStorage<Wry>>;
type CommunityService =
    BackendCommunitySkinService<BackendAccountClient, AndroidAccountStorage<Wry>>;
type CommunityResourceService =
    BackendCommunityResourceService<BackendAccountClient, AndroidAccountStorage<Wry>>;
type AiSkinService = BackendAiSkinService<BackendAccountClient, AndroidAccountStorage<Wry>>;

pub struct AccountState {
    session: Arc<Session>,
    pub(crate) platform: PluginHandle<Wry>,
    snapshot_directory: PathBuf,
    snapshot_previews: Arc<Mutex<HashMap<String, PendingSnapshot>>>,
    feedback: PluginHandle<Wry>,
    community: Arc<CommunityService>,
    resources: Arc<CommunityResourceService>,
    ai_skin: Arc<AiSkinService>,
    ai_skin_requests: Arc<Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

struct PendingSnapshot {
    account_id: String,
    path: PathBuf,
    metadata: SnapshotMetadata,
}

pub fn init() -> TauriPlugin<Wry> {
    Builder::new("account-storage")
        .setup(|app, api| {
            let handle = api.register_android_plugin("app.msime.client", "AccountPlugin")?;
            let platform = handle.clone();
            let feedback = handle.clone();
            let client = BackendAccountClient::new()?;
            let session = Arc::new(BackendAccountSession::new(
                client.clone(),
                AndroidAccountStorage(handle),
            ));
            let community = Arc::new(BackendCommunitySkinService::new(
                client,
                Arc::clone(&session),
            ));
            let resource_client = BackendAccountClient::new()?;
            let resources = Arc::new(BackendCommunityResourceService::new(
                resource_client,
                Arc::clone(&session),
            ));
            let ai_skin = Arc::new(BackendAiSkinService::new(
                BackendAccountClient::new()?,
                Arc::clone(&session),
            ));
            app.manage(AccountState {
                session,
                platform,
                snapshot_directory: app
                    .path()
                    .app_data_dir()?
                    .join("files/bootstrap/state/dictionary-snapshots"),
                snapshot_previews: Arc::new(Mutex::new(HashMap::new())),
                feedback,
                community,
                resources,
                ai_skin,
                ai_skin_requests: Arc::new(Mutex::new(HashMap::new())),
            });
            Ok(())
        })
        .build()
}

#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SnapshotMetadata {
    cloud_revision: i64,
    sha256: String,
    #[serde(skip_serializing)]
    file_sha256: String,
    bytes: u64,
    records: usize,
    entries: usize,
    overlays: usize,
    positions: usize,
    selections: usize,
}

struct StrictSnapshotValue {
    depth: usize,
}

impl<'de> DeserializeSeed<'de> for StrictSnapshotValue {
    type Value = Value;

    fn deserialize<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        struct SnapshotValueVisitor {
            depth: usize,
        }

        impl<'de> Visitor<'de> for SnapshotValueVisitor {
            type Value = Value;

            fn expecting(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                formatter.write_str("a strict JSON object value")
            }

            fn visit_bool<E>(self, value: bool) -> Result<Self::Value, E> {
                Ok(Value::Bool(value))
            }

            fn visit_i64<E>(self, value: i64) -> Result<Self::Value, E> {
                Ok(Value::Number(value.into()))
            }

            fn visit_u64<E>(self, value: u64) -> Result<Self::Value, E> {
                Ok(Value::Number(value.into()))
            }

            fn visit_f64<E>(self, _value: f64) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Err(E::custom("floating point values are not allowed"))
            }

            fn visit_str<E>(self, value: &str) -> Result<Self::Value, E> {
                Ok(Value::String(value.to_owned()))
            }

            fn visit_string<E>(self, value: String) -> Result<Self::Value, E> {
                Ok(Value::String(value))
            }

            fn visit_none<E>(self) -> Result<Self::Value, E> {
                Ok(Value::Null)
            }

            fn visit_unit<E>(self) -> Result<Self::Value, E> {
                Ok(Value::Null)
            }

            fn visit_seq<A>(self, _sequence: A) -> Result<Self::Value, A::Error>
            where
                A: serde::de::SeqAccess<'de>,
            {
                Err(serde::de::Error::custom("arrays are not allowed"))
            }

            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: MapAccess<'de>,
            {
                if self.depth > 1 {
                    return Err(serde::de::Error::custom("nested objects are not allowed"));
                }
                let mut object = serde_json::Map::new();
                while let Some(key) = map.next_key::<String>()? {
                    if object.contains_key(&key) {
                        return Err(serde::de::Error::custom("duplicate JSON key"));
                    }
                    let value = map.next_value_seed(StrictSnapshotValue {
                        depth: self.depth + 1,
                    })?;
                    object.insert(key, value);
                }
                Ok(Value::Object(object))
            }
        }

        deserializer.deserialize_any(SnapshotValueVisitor { depth: self.depth })
    }
}

fn parse_snapshot_object(bytes: &[u8]) -> Result<serde_json::Map<String, Value>, AccountError> {
    let mut deserializer = serde_json::Deserializer::from_slice(bytes);
    let value = StrictSnapshotValue { depth: 0 }
        .deserialize(&mut deserializer)
        .map_err(|_| AccountError::Invalid)?;
    deserializer.end().map_err(|_| AccountError::Invalid)?;
    value.as_object().cloned().ok_or(AccountError::Invalid)
}

fn snapshot_has_keys(map: &serde_json::Map<String, Value>, keys: &[&str]) -> bool {
    map.len() == keys.len() && keys.iter().all(|key| map.contains_key(*key))
}

fn snapshot_text<'a>(
    data: &'a serde_json::Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<&'a str, AccountError> {
    let value = data
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| {
            !value.is_empty()
                && value.len() <= maximum
                && !value
                    .bytes()
                    .any(|byte| matches!(byte, 0 | b'\t' | b'\n' | b'\r'))
        })
        .ok_or(AccountError::Invalid)?;
    Ok(value)
}

fn snapshot_integer(data: &serde_json::Map<String, Value>, key: &str) -> Result<i64, AccountError> {
    data.get(key)
        .and_then(Value::as_i64)
        .ok_or(AccountError::Invalid)
}

fn snapshot_timestamp(value: &str) -> bool {
    fn digits(bytes: &[u8], start: usize, end: usize) -> Option<u32> {
        (end <= bytes.len() && bytes[start..end].iter().all(u8::is_ascii_digit)).then(|| {
            bytes[start..end]
                .iter()
                .fold(0, |value, byte| value * 10 + u32::from(byte - b'0'))
        })
    }
    let bytes = value.as_bytes();
    if bytes.len() < 20
        || digits(bytes, 0, 4).is_none()
        || bytes.get(4) != Some(&b'-')
        || bytes.get(7) != Some(&b'-')
        || bytes.get(10) != Some(&b'T')
        || bytes.get(13) != Some(&b':')
        || bytes.get(16) != Some(&b':')
    {
        return false;
    }
    let year = digits(bytes, 0, 4).unwrap();
    let month = match digits(bytes, 5, 7) {
        Some(value) => value,
        None => return false,
    };
    let day = match digits(bytes, 8, 10) {
        Some(value) => value,
        None => return false,
    };
    let hour = match digits(bytes, 11, 13) {
        Some(value) => value,
        None => return false,
    };
    let minute = match digits(bytes, 14, 16) {
        Some(value) => value,
        None => return false,
    };
    let second = match digits(bytes, 17, 19) {
        Some(value) => value,
        None => return false,
    };
    let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    let days = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    if year == 0
        || !(1..=12).contains(&month)
        || day == 0
        || day > days[month as usize - 1]
        || hour >= 24
        || minute >= 60
        || second >= 60
    {
        return false;
    }
    let mut offset = 19;
    if matches!(bytes.get(offset), Some(b'.' | b',')) {
        offset += 1;
        let start = offset;
        while bytes.get(offset).is_some_and(u8::is_ascii_digit) {
            offset += 1;
        }
        if offset == start {
            return false;
        }
    }
    let zone = &bytes[offset..];
    if zone == b"Z" {
        return true;
    }
    if zone.len() != 6
        || !matches!(zone[0], b'+' | b'-')
        || !zone[1].is_ascii_digit()
        || !zone[2].is_ascii_digit()
        || zone[3] != b':'
        || !zone[4].is_ascii_digit()
        || !zone[5].is_ascii_digit()
    {
        return false;
    }
    let zone_hour = u32::from(zone[1] - b'0') * 10 + u32::from(zone[2] - b'0');
    let zone_minute = u32::from(zone[4] - b'0') * 10 + u32::from(zone[5] - b'0');
    zone_hour < 24 && zone_minute < 60
}

fn inspect_snapshot_record(
    map: &serde_json::Map<String, Value>,
    revision: i64,
    entry_keys: &mut HashMap<(String, String, String), i64>,
    entry_ids: &mut HashSet<String>,
    overlays: &mut HashMap<(String, String, String), (bool, bool, i64)>,
    positions: &mut HashSet<(String, String, String)>,
    position_slots: &mut HashSet<(String, i64)>,
    selections: &mut HashSet<(String, String, String)>,
) -> Result<u8, AccountError> {
    let kind = map
        .get("type")
        .and_then(Value::as_str)
        .ok_or(AccountError::Invalid)?;
    let data = map
        .get("data")
        .and_then(Value::as_object)
        .ok_or(AccountError::Invalid)?;
    let code = snapshot_text(data, "code", 512)?.to_owned();
    let word = snapshot_text(data, "word", 2048)?.to_owned();
    match kind {
        "entry" | "overlay" => {
            let outer_keys_valid = if kind == "overlay" {
                snapshot_has_keys(map, &["type", "data", "deleted"])
            } else {
                snapshot_has_keys(map, &["type", "data"])
            };
            if !outer_keys_valid {
                return Err(AccountError::Invalid);
            }
            let deleted = if kind == "overlay" {
                map.get("deleted")
                    .and_then(Value::as_bool)
                    .ok_or(AccountError::Invalid)?
            } else {
                false
            };
            let expected = [
                "id",
                "kind",
                "code",
                "word",
                "weight",
                "revision",
                "updated_at",
            ];
            let mut data_keys = data.keys().map(String::as_str).collect::<HashSet<_>>();
            if data_keys.remove("user_inserted") {
                let user_inserted = data
                    .get("user_inserted")
                    .and_then(Value::as_bool)
                    .ok_or(AccountError::Invalid)?;
                if kind == "entry" && !user_inserted {
                    return Err(AccountError::Invalid);
                }
            }
            if data_keys.len() != expected.len()
                || expected.iter().any(|key| !data_keys.contains(key))
            {
                return Err(AccountError::Invalid);
            }
            let dictionary_kind = data
                .get("kind")
                .and_then(Value::as_str)
                .filter(|value| matches!(*value, "pinyin" | "wubi" | "english" | "quick"))
                .ok_or(AccountError::Invalid)?
                .to_owned();
            let id = data
                .get("id")
                .and_then(Value::as_str)
                .ok_or(AccountError::Invalid)?
                .to_owned();
            if kind == "entry"
                && (id.is_empty()
                    || id.len() > 128
                    || id.bytes()
                        .any(|byte| matches!(byte, 0 | b'\t' | b'\n' | b'\r')))
            {
                return Err(AccountError::Invalid);
            }
            let weight = snapshot_integer(data, "weight")?;
            let record_revision = snapshot_integer(data, "revision")?;
            if !(0..=100_000_000).contains(&weight)
                || (weight == 0 && !deleted)
                || !(1..=revision).contains(&record_revision)
                || !snapshot_timestamp(
                    data.get("updated_at")
                        .and_then(Value::as_str)
                        .ok_or(AccountError::Invalid)?,
                )
            {
                return Err(AccountError::Invalid);
            }
            let identity = (dictionary_kind, code, word);
            if kind == "entry" {
                if entry_keys.insert(identity, weight).is_some() || !entry_ids.insert(id) {
                    return Err(AccountError::Invalid);
                }
            } else {
                let user_inserted = data
                    .get("user_inserted")
                    .and_then(Value::as_bool)
                    .unwrap_or(true);
                if overlays
                    .insert(identity, (deleted, user_inserted, weight))
                    .is_some()
                {
                    return Err(AccountError::Invalid);
                }
            }
            Ok(if kind == "entry" { 1 } else { 2 })
        }
        "position" | "selection" => {
            if !snapshot_has_keys(map, &["type", "data"]) {
                return Err(AccountError::Invalid);
            }
            let value_key = if kind == "position" {
                "position"
            } else {
                "count"
            };
            if !snapshot_has_keys(data, &["context", "code", "word", value_key]) {
                return Err(AccountError::Invalid);
            }
            let context = snapshot_text(data, "context", 512)?.to_owned();
            if context.len() + code.len() + word.len() > 2048 {
                return Err(AccountError::Invalid);
            }
            let identity = (context.clone(), code, word);
            if kind == "position" {
                let position = snapshot_integer(data, "position")?;
                if !(1..=5).contains(&position)
                    || !positions.insert(identity)
                    || !position_slots.insert((context, position))
                {
                    return Err(AccountError::Invalid);
                }
                Ok(3)
            } else {
                let count = snapshot_integer(data, "count")?;
                if !(0..=10).contains(&count) || !selections.insert(identity) {
                    return Err(AccountError::Invalid);
                }
                Ok(4)
            }
        }
        _ => Err(AccountError::Invalid),
    }
}

fn inspect_snapshot(path: &std::path::Path) -> Result<SnapshotMetadata, AccountError> {
    const MAX_BYTES: u64 = 512 * 1024 * 1024;
    let file = File::open(path).map_err(|_| AccountError::Unavailable)?;
    let mut reader = BufReader::with_capacity(65_536, file);
    let mut line = Vec::with_capacity(65_536);
    let mut total_bytes = 0u64;
    let mut records = 0usize;
    let mut counts = [0usize; 4];
    let mut category = 0u8;
    let mut revision = None;
    let mut digest = Sha256::new();
    let mut file_digest = Sha256::new();
    let mut checksum = None;
    let mut entry_keys = HashMap::new();
    let mut entry_ids = HashSet::new();
    let mut overlays = HashMap::new();
    let mut positions = HashSet::new();
    let mut position_slots = HashSet::new();
    let mut selections = HashSet::new();
    loop {
        line.clear();
        let complete = loop {
            let chunk = reader.fill_buf().map_err(|_| AccountError::Unavailable)?;
            if chunk.is_empty() {
                break false;
            }
            if let Some(index) = chunk.iter().position(|byte| *byte == b'\n') {
                if line.len() + index + 1 > 65_536 {
                    return Err(AccountError::Invalid);
                }
                line.extend_from_slice(&chunk[..=index]);
                reader.consume(index + 1);
                break true;
            }
            if line.len() + chunk.len() >= 65_536 {
                return Err(AccountError::Invalid);
            }
            line.extend_from_slice(chunk);
            let length = chunk.len();
            reader.consume(length);
        };
        let has_newline = complete;
        file_digest.update(&line);
        if has_newline {
            line.pop();
            if line.ends_with(b"\r") {
                return Err(AccountError::Invalid);
            }
        } else if line.is_empty() {
            break;
        }
        total_bytes = total_bytes
            .checked_add(line.len() as u64 + u64::from(has_newline))
            .ok_or(AccountError::Unavailable)?;
        if total_bytes > MAX_BYTES || line.is_empty() {
            return Err(AccountError::Invalid);
        }
        let map = parse_snapshot_object(&line)?;
        let kind = map
            .get("type")
            .and_then(Value::as_str)
            .ok_or(AccountError::Invalid)?;
        match kind {
            "header" => {
                if records != 0
                    || revision.is_some()
                    || !snapshot_has_keys(&map, &["type", "format", "version", "revision"])
                    || map.get("format").and_then(Value::as_str)
                        != Some("msime-dictionary-snapshot")
                    || map.get("version").and_then(Value::as_i64) != Some(1)
                {
                    return Err(AccountError::Invalid);
                }
                revision = Some(
                    map.get("revision")
                        .and_then(Value::as_i64)
                        .filter(|value| *value >= 0)
                        .ok_or(AccountError::Invalid)?,
                );
            }
            "entry" | "overlay" | "position" | "selection" => {
                let snapshot_revision = revision.ok_or(AccountError::Invalid)?;
                if checksum.is_some() {
                    return Err(AccountError::Invalid);
                }
                let next = inspect_snapshot_record(
                    &map,
                    snapshot_revision,
                    &mut entry_keys,
                    &mut entry_ids,
                    &mut overlays,
                    &mut positions,
                    &mut position_slots,
                    &mut selections,
                )?;
                if next < category {
                    return Err(AccountError::Invalid);
                }
                category = next;
                counts[(next - 1) as usize] = counts[(next - 1) as usize]
                    .checked_add(1)
                    .ok_or(AccountError::Unavailable)?;
                records = records.checked_add(1).ok_or(AccountError::Unavailable)?;
                if records > 500_000 || counts[0] > 100_000 {
                    return Err(AccountError::Invalid);
                }
                digest.update(&line);
                digest.update([b'\n']);
            }
            "footer" => {
                if revision.is_none()
                    || checksum.is_some()
                    || !snapshot_has_keys(&map, &["type", "records", "sha256"])
                {
                    return Err(AccountError::Invalid);
                }
                let expected_records = map
                    .get("records")
                    .and_then(Value::as_u64)
                    .and_then(|value| usize::try_from(value).ok())
                    .ok_or(AccountError::Invalid)?;
                let expected_sha = map
                    .get("sha256")
                    .and_then(Value::as_str)
                    .filter(|value| {
                        value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit())
                    })
                    .ok_or(AccountError::Invalid)?;
                let actual = format!("{:x}", digest.finalize());
                if expected_records != records || expected_sha != actual {
                    return Err(AccountError::Invalid);
                }
                checksum = Some(expected_sha.to_owned());
            }
            _ => return Err(AccountError::Invalid),
        }
        if !has_newline {
            break;
        }
    }
    let revision = revision.ok_or(AccountError::Invalid)?;
    let sha256 = checksum.ok_or(AccountError::Invalid)?;
    for (identity, entry_weight) in &entry_keys {
        let Some((deleted, user_inserted, weight)) = overlays.get(identity) else {
            return Err(AccountError::Invalid);
        };
        if *deleted || !*user_inserted || *weight != *entry_weight {
            return Err(AccountError::Invalid);
        }
    }
    for (identity, (deleted, user_inserted, weight)) in &overlays {
        if !*deleted && *user_inserted {
            let Some(entry_weight) = entry_keys.get(identity) else {
                return Err(AccountError::Invalid);
            };
            if *entry_weight != *weight {
                return Err(AccountError::Invalid);
            }
        }
    }
    Ok(SnapshotMetadata {
        cloud_revision: revision,
        sha256,
        file_sha256: format!("{:x}", file_digest.finalize()),
        bytes: total_bytes,
        records,
        entries: counts[0],
        overlays: counts[1],
        positions: counts[2],
        selections: counts[3],
    })
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EnqueueSnapshotRequest {
    source: String,
    account_id: String,
    cloud_revision: i64,
    expected_local_version: String,
    file_sha256: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CancelSnapshotRequest {
    account_id: String,
}

fn snapshot_command_error() -> super::CommandError {
    super::CommandError {
        code: "snapshot_unavailable",
    }
}

fn snapshot_response_without_account(mut value: Value) -> Result<Value, super::CommandError> {
    let object = value.as_object_mut().ok_or_else(snapshot_command_error)?;
    if let Some(request) = object.get_mut("request").and_then(Value::as_object_mut) {
        request.remove("accountId");
    }
    Ok(value)
}

fn clear_snapshot_previews(previews: &Arc<Mutex<HashMap<String, PendingSnapshot>>>) {
    let Ok(mut pending) = previews.lock() else { return };
    for item in pending.drain().map(|(_, item)| item) {
        let _ = fs::remove_file(item.path);
    }
}

async fn dictionary_snapshot_preview(
    state: State<'_, AccountState>,
) -> Result<Value, super::CommandError> {
    let session = Arc::clone(&state.session);
    let directory = state.snapshot_directory.clone();
    let previews = Arc::clone(&state.snapshot_previews);
    let token = Uuid::new_v4().to_string();
    let (account_id, path, metadata) = tauri::async_runtime::spawn_blocking(move || {
        fs::create_dir_all(&directory).map_err(|_| AccountError::Unavailable)?;
        if let Ok(files) = fs::read_dir(&directory) {
            for file in files.flatten() {
                if file.file_name().to_string_lossy().starts_with("download-") {
                    let _ = fs::remove_file(file.path());
                }
            }
        }
        let profile = session.profile()?;
        let path = directory.join(format!("download-{token}.ndjson"));
        let result = session.dictionary_snapshot_to_file(&path).and_then(|_| inspect_snapshot(&path));
        match result {
            Ok(metadata) => Ok((profile.user.id, path, metadata)),
            Err(error) => {
                let _ = fs::remove_file(&path);
                Err(error)
            }
        }
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })?;
    let old = {
        let mut pending = previews.lock().map_err(|_| snapshot_command_error())?;
        let old = pending.drain().map(|(_, item)| item.path).collect::<Vec<_>>();
        pending.insert(token.clone(), PendingSnapshot { account_id, path, metadata: metadata.clone() });
        old
    };
    for path in old { let _ = fs::remove_file(path); }
    Ok(serde_json::json!({
        "previewToken": token,
        "snapshot": metadata,
    }))
}

async fn dictionary_snapshot_enqueue(
    state: State<'_, AccountState>,
    token: String,
) -> Result<Value, super::CommandError> {
    let parsed = Uuid::parse_str(&token).map_err(|_| super::CommandError { code: "snapshot_invalid" })?;
    let pending = {
        let mut previews = state.snapshot_previews.lock().map_err(|_| snapshot_command_error())?;
        previews.remove(&parsed.to_string()).ok_or_else(|| super::CommandError { code: "snapshot_invalid" })?
    };
    let session = Arc::clone(&state.session);
    let platform = state.platform.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        let path = pending.path.clone();
        let result = (|| {
            let profile = session.profile()?;
            if profile.user.id != pending.account_id {
                return Err(AccountError::Conflict);
            }
            let changes = session.dictionary_changes(pending.metadata.cloud_revision, 1)?;
            if !changes.changes.is_empty() {
                return Err(AccountError::Conflict);
            }
            let state = platform
                .run_mobile_plugin::<Value>("snapshotState", ())
                .map_err(|_| AccountError::Unavailable)?;
            let expected = state
                .get("localVersion")
                .and_then(Value::as_str)
                .ok_or(AccountError::Conflict)?
                .to_owned();
            let request = EnqueueSnapshotRequest {
                source: path.to_string_lossy().into_owned(),
                account_id: pending.account_id,
                cloud_revision: pending.metadata.cloud_revision,
                expected_local_version: expected,
                file_sha256: pending.metadata.file_sha256.clone(),
            };
            platform
                .run_mobile_plugin::<Value>("enqueueSnapshot", request)
                .map_err(|_| AccountError::Unavailable)
        })();
        let _ = fs::remove_file(path);
        result
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })?;
    snapshot_response_without_account(result)
}

async fn dictionary_snapshot_export(
    state: State<'_, AccountState>,
) -> Result<Value, super::CommandError> {
    let session = Arc::clone(&state.session);
    let directory = state.snapshot_directory.clone();
    let token = Uuid::new_v4().to_string();
    tauri::async_runtime::spawn_blocking(move || {
        fs::create_dir_all(&directory).map_err(|_| AccountError::Unavailable)?;
        let path = directory.join(format!("export-{token}.ndjson"));
        let result = session
            .dictionary_snapshot_to_file(&path)
            .and_then(|_| inspect_snapshot(&path))
            .and_then(|metadata| {
                let text = fs::read_to_string(&path).map_err(|_| AccountError::Unavailable)?;
                Ok(serde_json::json!({
                    "text": text,
                    "filename": "msime-dictionary-snapshot.ndjson",
                    "snapshot": metadata,
                }))
            });
        let _ = fs::remove_file(&path);
        result
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })
}

async fn dictionary_snapshot_restore_preview(
    state: State<'_, AccountState>,
    text: String,
) -> Result<Value, super::CommandError> {
    let session = Arc::clone(&state.session);
    let directory = state.snapshot_directory.clone();
    let token = Uuid::new_v4().to_string();
    tauri::async_runtime::spawn_blocking(move || {
        fs::create_dir_all(&directory).map_err(|_| AccountError::Unavailable)?;
        let path = directory.join(format!("restore-{token}.ndjson"));
        let result = fs::write(&path, text.as_bytes())
            .map_err(|_| AccountError::Unavailable)
            .and_then(|_| inspect_snapshot(&path))
            .and_then(|metadata| {
                session
                    .dictionary_catalog(DictionaryKind::Quick, "", 0, "pinyin", "xiaohe")
                    .map(|page| serde_json::json!({
                        "snapshot": metadata,
                        "expectedRevision": page.revision,
                    }))
            });
        let _ = fs::remove_file(&path);
        result
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })
}

async fn dictionary_snapshot_restore(
    state: State<'_, AccountState>,
    text: String,
    expected_sha256: String,
    revision: i64,
) -> Result<Value, super::CommandError> {
    let session = Arc::clone(&state.session);
    let directory = state.snapshot_directory.clone();
    let token = Uuid::new_v4().to_string();
    tauri::async_runtime::spawn_blocking(move || {
        fs::create_dir_all(&directory).map_err(|_| AccountError::Unavailable)?;
        let path = directory.join(format!("restore-{token}.ndjson"));
        let result = fs::write(&path, text.as_bytes())
            .map_err(|_| AccountError::Unavailable)
            .and_then(|_| inspect_snapshot(&path))
            .and_then(|metadata| {
                if metadata.sha256 != expected_sha256 {
                    return Err(AccountError::Invalid);
                }
                session
                    .restore_dictionary_snapshot(text.as_bytes(), revision)
                    .and_then(|result| {
                        Ok(serde_json::json!({
                            "revision": result.revision,
                            "reset": result.reset,
                        }))
                    })
            });
        let _ = fs::remove_file(&path);
        result
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })
}

async fn dictionary_snapshot_status(
    state: State<'_, AccountState>,
) -> Result<Value, super::CommandError> {
    let platform = state.platform.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        platform
            .run_mobile_plugin::<Value>("snapshotState", ())
            .map_err(|_| snapshot_command_error())
    })
    .await
    .map_err(|_| snapshot_command_error())??;
    snapshot_response_without_account(result)
}

async fn dictionary_snapshot_cancel(
    state: State<'_, AccountState>,
) -> Result<Value, super::CommandError> {
    let session = Arc::clone(&state.session);
    let platform = state.platform.clone();
    let previews = Arc::clone(&state.snapshot_previews);
    let account_id = tauri::async_runtime::spawn_blocking(move || {
        session.profile().map(|profile| profile.user.id)
    })
    .await
    .map_err(|_| snapshot_command_error())?
    .map_err(|error| super::CommandError { code: error.code() })?;
    let old = {
        let mut pending = previews.lock().map_err(|_| snapshot_command_error())?;
        pending.drain().map(|(_, item)| item.path).collect::<Vec<_>>()
    };
    for path in old { let _ = fs::remove_file(path); }
    let result = tauri::async_runtime::spawn_blocking(move || {
        platform
            .run_mobile_plugin::<Value>("cancelSnapshot", CancelSnapshotRequest { account_id })
            .map_err(|_| snapshot_command_error())
    })
    .await
    .map_err(|_| snapshot_command_error())??;
    snapshot_response_without_account(result)
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatusResponse {
    user: Option<UserResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct UserResponse {
    id: String,
    display_name: String,
    created_at: String,
}

impl From<AccountUser> for UserResponse {
    fn from(user: AccountUser) -> Self {
        Self {
            id: user.id,
            display_name: user.display_name,
            created_at: user.created_at,
        }
    }
}

#[derive(Serialize)]
pub struct ProvidersResponse {
    email: bool,
    phone: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChallengeResponse {
    challenge_id: String,
    expires_in: u64,
}

impl From<AccountChallenge> for ChallengeResponse {
    fn from(challenge: AccountChallenge) -> Self {
        Self {
            challenge_id: challenge.challenge_id,
            expires_in: challenge.expires_in,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProfileResponse {
    user: UserResponse,
    providers: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatModelResponse {
    id: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatModelsResponse {
    data: Vec<ChatModelResponse>,
    default_model: String,
}

impl From<AccountChatModels> for ChatModelsResponse {
    fn from(models: AccountChatModels) -> Self {
        Self {
            data: models
                .data
                .into_iter()
                .map(|model| ChatModelResponse { id: model.id })
                .collect(),
            default_model: models.default_model,
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ChatResponse {
    content: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppIconResponse {
    pub supported: bool,
    pub selected: String,
}

#[derive(Serialize)]
struct AppIconRequest<'a> {
    style: &'a str,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PreferenceSchemaResponse {
    fields: BTreeMap<String, msime_client_core::account::AccountPreferenceField>,
    maximum_bytes: usize,
    update_mode: String,
    revision_required: bool,
}

impl From<AccountPreferenceSchema> for PreferenceSchemaResponse {
    fn from(schema: AccountPreferenceSchema) -> Self {
        Self {
            fields: schema.fields,
            maximum_bytes: schema.maximum_bytes,
            update_mode: schema.update_mode,
            revision_required: schema.revision_required,
        }
    }
}

impl From<AccountProfile> for ProfileResponse {
    fn from(profile: AccountProfile) -> Self {
        let mut providers = Vec::new();
        for identity in profile.identities {
            if !providers.contains(&identity.provider) {
                providers.push(identity.provider);
            }
        }
        Self {
            user: profile.user.into(),
            providers,
        }
    }
}

async fn call<T, F>(state: State<'_, AccountState>, operation: F) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&Session) -> Result<T, AccountError> + Send + 'static,
{
    let session = Arc::clone(&state.session);
    tauri::async_runtime::spawn_blocking(move || operation(&session))
        .await
        .map_err(|_| super::CommandError {
            code: "account_unavailable",
        })?
        .map_err(|error| super::CommandError { code: error.code() })
}

fn community_error(error: AccountError) -> super::CommandError {
    super::CommandError {
        code: match error {
            AccountError::Invalid => "community_invalid",
            AccountError::Unauthorized => "community_unauthorized",
            AccountError::Forbidden => "community_forbidden",
            AccountError::NotFound => "community_not_found",
            AccountError::RateLimited => "community_rate_limited",
            AccountError::Cancelled => "community_cancelled",
            AccountError::Storage => "community_storage",
            AccountError::Conflict => "community_conflict",
            AccountError::Unavailable => "community_unavailable",
        },
    }
}

fn ai_skin_error(error: AiSkinError) -> super::CommandError {
    let code = match error {
        AiSkinError::Cancelled => "ai_skin_cancelled",
        AiSkinError::InvalidResponse => "ai_skin_invalid",
        AiSkinError::Account(error) => error.code(),
    };
    super::CommandError { code }
}

fn valid_ai_skin_request_id(value: &str) -> bool {
    (1..=96).contains(&value.len())
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct AiSkinProgress {
    request_id: String,
    completed: usize,
}

#[tauri::command]
pub async fn ai_skin_generate(
    app: tauri::AppHandle<Wry>,
    state: State<'_, AccountState>,
    request_id: String,
    prompt: String,
) -> Result<Vec<AiSkinProposal>, super::CommandError> {
    if !valid_ai_skin_request_id(&request_id) {
        return Err(super::CommandError {
            code: "ai_skin_invalid",
        });
    }
    let cancelled = Arc::new(AtomicBool::new(false));
    {
        let mut requests = state
            .ai_skin_requests
            .lock()
            .map_err(|_| super::CommandError {
                code: "ai_skin_unavailable",
            })?;
        if requests
            .insert(request_id.clone(), Arc::clone(&cancelled))
            .is_some()
        {
            return Err(super::CommandError {
                code: "ai_skin_busy",
            });
        }
    }
    let service = Arc::clone(&state.ai_skin);
    let progress_app = app.clone();
    let progress_request_id = request_id.clone();
    let result = tauri::async_runtime::spawn_blocking(move || {
        service.generate(&prompt, &cancelled, move |completed| {
            let _ = progress_app.emit(
                "ai-skin-progress",
                AiSkinProgress {
                    request_id: progress_request_id.clone(),
                    completed,
                },
            );
        })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_skin_unavailable",
    })?
    .map_err(ai_skin_error);
    if let Ok(mut requests) = state.ai_skin_requests.lock() {
        requests.remove(&request_id);
    }
    result
}

#[tauri::command]
pub async fn ai_skin_cancel(
    state: State<'_, AccountState>,
    request_id: String,
) -> Result<(), super::CommandError> {
    if !valid_ai_skin_request_id(&request_id) {
        return Err(super::CommandError {
            code: "ai_skin_invalid",
        });
    }
    let requests = state
        .ai_skin_requests
        .lock()
        .map_err(|_| super::CommandError {
            code: "ai_skin_unavailable",
        })?;
    if let Some(cancelled) = requests.get(&request_id) {
        cancelled.store(true, Ordering::Release);
    }
    Ok(())
}

async fn community_call<T, F>(
    state: State<'_, AccountState>,
    operation: F,
) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&CommunityService) -> Result<T, AccountError> + Send + 'static,
{
    let service = Arc::clone(&state.community);
    tauri::async_runtime::spawn_blocking(move || operation(&service))
        .await
        .map_err(|_| super::CommandError {
            code: "community_unavailable",
        })?
        .map_err(community_error)
}

fn custom_skin_error(error: CustomSkinLibraryError) -> super::CommandError {
    super::CommandError {
        code: match error {
            CustomSkinLibraryError::Full => "community_skin_library_full",
            CustomSkinLibraryError::InvalidName => "community_skin_invalid_name",
            CustomSkinLibraryError::DuplicateName => "community_skin_duplicate_name",
            CustomSkinLibraryError::NotFound => "community_skin_not_found",
            CustomSkinLibraryError::Json(_) | CustomSkinLibraryError::Invalid => {
                "community_skin_library_format"
            }
            CustomSkinLibraryError::Io(_) => "community_storage",
        },
    }
}

fn trial_error(error: KeyboardSkinTrialError) -> super::CommandError {
    super::CommandError {
        code: match error {
            KeyboardSkinTrialError::Io(_) | KeyboardSkinTrialError::Preferences(_) => {
                "community_storage"
            }
            KeyboardSkinTrialError::Json(_) | KeyboardSkinTrialError::Invalid => {
                "community_trial_format"
            }
        },
    }
}

fn resource_library_error(error: CommunityResourceLibraryError) -> super::CommandError {
    super::CommandError {
        code: match error {
            CommunityResourceLibraryError::Io(_) => "community_storage",
            CommunityResourceLibraryError::Json(_) | CommunityResourceLibraryError::Invalid => {
                "community_resource_library_format"
            }
        },
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CommunitySkinDownloadResponse {
    skin: SavedTouchKeyboardSkin,
    trial: KeyboardSkinTrial,
}

#[tauri::command]
pub async fn community_skin_list(
    state: State<'_, AccountState>,
    offset: usize,
    search: String,
) -> Result<CommunitySkinPage, super::CommandError> {
    community_call(state, move |service| service.list(offset, &search)).await
}

#[tauri::command]
pub async fn community_skin_detail(
    state: State<'_, AccountState>,
    id: String,
) -> Result<CommunitySkin, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.detail(id)).await
}

#[tauri::command]
pub async fn community_skin_download(
    state: State<'_, AccountState>,
    library: State<'_, CustomSkinLibraryStore>,
    trials: State<'_, KeyboardSkinTrialStore>,
    id: String,
    name: String,
) -> Result<CommunitySkinDownloadResponse, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    let service = Arc::clone(&state.community);
    let library = library.inner().clone();
    let trials = trials.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let design = service.download(id).map_err(community_error)?;
        let (trial, _) = trials.begin(&name, design.clone()).map_err(trial_error)?;
        let skin = match library.import_download(id, &name, design) {
            Ok(skin) => skin,
            Err(error) => {
                let _ = trials.finish(trial.id, false);
                return Err(custom_skin_error(error));
            }
        };
        Ok(CommunitySkinDownloadResponse { skin, trial })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "community_unavailable",
    })?
}

#[tauri::command]
pub async fn community_skin_rate(
    state: State<'_, AccountState>,
    id: String,
    stars: u8,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.rate(id, stars)).await
}

#[tauri::command]
pub async fn community_skin_publish(
    state: State<'_, AccountState>,
    id: String,
    name: String,
    description: String,
    design: TouchKeyboardSkinDesign,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| {
        service.publish(id, &name, &description, &design)
    })
    .await
}

#[tauri::command]
pub async fn community_skin_unpublish(
    state: State<'_, AccountState>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    community_call(state, move |service| service.unpublish(id)).await
}

#[tauri::command]
pub async fn community_skin_finish_trial(
    trials: State<'_, KeyboardSkinTrialStore>,
    id: String,
    keep: bool,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError {
        code: "community_invalid",
    })?;
    let trials = trials.inner().clone();
    tauri::async_runtime::spawn_blocking(move || trials.finish(id, keep).map(|_| ()))
        .await
        .map_err(|_| super::CommandError {
            code: "community_storage",
        })?
        .map_err(trial_error)
}

fn resource_scope(value: &str) -> Result<CommunityResourceScope, super::CommandError> {
    match value {
        "" => Ok(CommunityResourceScope::All),
        "mine" => Ok(CommunityResourceScope::Mine),
        "saved" => Ok(CommunityResourceScope::Saved),
        _ => Err(super::CommandError { code: "community_invalid" }),
    }
}

async fn resource_call<T, F>(
    state: State<'_, AccountState>,
    operation: F,
) -> Result<T, super::CommandError>
where
    T: Send + 'static,
    F: FnOnce(&CommunityResourceService) -> Result<T, AccountError> + Send + 'static,
{
    let service = Arc::clone(&state.resources);
    tauri::async_runtime::spawn_blocking(move || operation(&service))
        .await
        .map_err(|_| super::CommandError { code: "community_unavailable" })?
        .map_err(community_error)
}

#[tauri::command]
pub async fn community_resource_list(
    state: State<'_, AccountState>,
    kind: CommunityResourceKind,
    scope: String,
    search: String,
    offset: usize,
) -> Result<CommunityResourcePage, super::CommandError> {
    let scope = resource_scope(&scope)?;
    resource_call(state, move |service| service.list(kind, scope, &search, offset)).await
}

#[tauri::command]
pub async fn community_resource_detail(
    state: State<'_, AccountState>,
    id: String,
) -> Result<CommunityResource, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.detail(id)).await
}

#[tauri::command]
pub async fn community_resource_publish(
    state: State<'_, AccountState>,
    id: String,
    kind: CommunityResourceKind,
    name: String,
    description: String,
    content: CommunityResourceContent,
    revision: u32,
) -> Result<CommunityResourcePublication, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.publish(id, kind, &name, &description, &content, revision)).await
}

#[tauri::command]
pub async fn community_resource_apply(
    state: State<'_, AccountState>,
    id: String,
    resource_revision: u32,
) -> Result<CommunityResourceApplication, super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.apply(id, resource_revision)).await
}

#[tauri::command]
pub async fn community_resource_save(
    state: State<'_, AccountState>,
    id: String,
    saved: bool,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.save(id, saved)).await
}

#[tauri::command]
pub async fn community_resource_rate(
    state: State<'_, AccountState>,
    id: String,
    stars: u8,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.rate(id, stars)).await
}

#[tauri::command]
pub async fn community_resource_unpublish(
    state: State<'_, AccountState>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    resource_call(state, move |service| service.delete(id)).await
}

#[tauri::command]
pub async fn community_resource_store_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    item: CommunityResource,
) -> Result<(), super::CommandError> {
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.save_reply(item))
        .await
        .map_err(|_| super::CommandError { code: "community_storage" })?
        .map_err(resource_library_error)
}

#[tauri::command]
pub async fn community_resource_remove_reply(
    library: State<'_, CommunityResourceLibraryStore>,
    id: String,
) -> Result<(), super::CommandError> {
    let id = uuid::Uuid::parse_str(&id).map_err(|_| super::CommandError { code: "community_invalid" })?;
    let library = library.inner().clone();
    tauri::async_runtime::spawn_blocking(move || library.remove(id))
        .await
        .map_err(|_| super::CommandError { code: "community_storage" })?
        .map_err(resource_library_error)
}

#[tauri::command]
pub async fn account_status(
    state: State<'_, AccountState>,
) -> Result<StatusResponse, super::CommandError> {
    call(state, |session| {
        session.status().map(|user| StatusResponse {
            user: user.map(Into::into),
        })
    })
    .await
}

#[tauri::command]
pub async fn android_open_input_method_settings(
    state: State<'_, AccountState>,
) -> Result<(), super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<()>("openInputMethodSettings", ())
            .map_err(|_| super::CommandError {
                code: "system_settings",
            })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "system_settings",
    })?
}

#[tauri::command]
pub async fn android_show_input_method_picker(
    state: State<'_, AccountState>,
) -> Result<(), super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<()>("showInputMethodPicker", ())
            .map_err(|_| super::CommandError {
                code: "input_method_picker",
            })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "input_method_picker",
    })?
}

#[tauri::command]
pub async fn android_bootstrap_status(
    state: State<'_, AccountState>,
) -> Result<bool, super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<Value>("bootstrapStatus", ())
            .map_err(|_| super::CommandError { code: "bootstrap" })?
            .get("ready")
            .and_then(Value::as_bool)
            .ok_or(super::CommandError { code: "bootstrap" })
    })
    .await
    .map_err(|_| super::CommandError { code: "bootstrap" })?
}

#[tauri::command]
pub async fn android_prepare_bootstrap(
    state: State<'_, AccountState>,
) -> Result<(), super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<Value>("prepareBootstrap", ())
            .map_err(|_| super::CommandError { code: "bootstrap" })?
            .get("ready")
            .and_then(Value::as_bool)
            .filter(|ready| *ready)
            .map(|_| ())
            .ok_or(super::CommandError { code: "bootstrap" })
    })
    .await
    .map_err(|_| super::CommandError { code: "bootstrap" })?
}

#[tauri::command]
pub async fn ai_models(
    state: State<'_, AccountState>,
    endpoint: String,
    token: String,
) -> Result<Vec<String>, super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let response = plugin
            .run_mobile_plugin::<Value>(
                "aiModels",
                AiModelsRequest {
                    endpoint: &endpoint,
                    token: &token,
                },
            )
            .map_err(|_| super::CommandError {
                code: "ai_models_unavailable",
            })?;
        response
            .get("models")
            .cloned()
            .and_then(|value| serde_json::from_value(value).ok())
            .ok_or(super::CommandError {
                code: "ai_models_invalid",
            })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_models_unavailable",
    })?
}

#[tauri::command]
pub async fn ai_test(
    state: State<'_, AccountState>,
    endpoint: String,
    model: String,
    prompt: String,
    token: String,
    text: String,
) -> Result<String, super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        let response = plugin
            .run_mobile_plugin::<Value>(
                "aiTest",
                AiTestRequest {
                    endpoint: &endpoint,
                    model: &model,
                    prompt: &prompt,
                    token: &token,
                    text: &text,
                },
            )
            .map_err(|_| super::CommandError {
                code: "ai_test_unavailable",
            })?;
        response
            .get("text")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or(super::CommandError {
                code: "ai_test_invalid",
            })
    })
    .await
    .map_err(|_| super::CommandError {
        code: "ai_test_unavailable",
    })?
}

#[tauri::command]
pub async fn account_providers(
    state: State<'_, AccountState>,
) -> Result<ProvidersResponse, super::CommandError> {
    call(state, |session| {
        session.providers().map(|providers| ProvidersResponse {
            email: providers.get("email") == Some(&true),
            phone: providers.get("phone") == Some(&true) || providers.get("sms") == Some(&true),
        })
    })
    .await
}

#[tauri::command]
pub async fn account_request_code(
    state: State<'_, AccountState>,
    provider: String,
    target: String,
) -> Result<ChallengeResponse, super::CommandError> {
    call(state, move |session| {
        session
            .request_code(&provider, &target)
            .map(ChallengeResponse::from)
    })
    .await
}

#[tauri::command]
pub async fn account_login(
    state: State<'_, AccountState>,
    challenge_id: String,
    code: String,
) -> Result<StatusResponse, super::CommandError> {
    call(state, move |session| {
        session
            .sign_in(&challenge_id, &code)
            .map(|user| StatusResponse {
                user: Some(user.into()),
            })
    })
    .await
}

#[tauri::command]
pub async fn account_profile(
    state: State<'_, AccountState>,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, |session| {
        session.profile().map(ProfileResponse::from)
    })
    .await
}

#[tauri::command]
pub async fn account_chat_models(
    state: State<'_, AccountState>,
) -> Result<ChatModelsResponse, super::CommandError> {
    call(state, |session| session.chat_models().map(Into::into)).await
}

#[tauri::command]
pub async fn account_chat(
    state: State<'_, AccountState>,
    messages: Vec<AccountChatMessage>,
    model: String,
) -> Result<ChatResponse, super::CommandError> {
    call(state, move |session| {
        session
            .chat(&messages, &model)
            .map(|content| ChatResponse { content })
    })
    .await
}

#[tauri::command]
pub async fn account_rename(
    state: State<'_, AccountState>,
    display_name: String,
) -> Result<ProfileResponse, super::CommandError> {
    call(state, move |session| {
        session.rename(&display_name).map(ProfileResponse::from)
    })
    .await
}

#[tauri::command]
pub async fn account_logout(
    state: State<'_, AccountState>,
    all: bool,
) -> Result<(), super::CommandError> {
    let previews = Arc::clone(&state.snapshot_previews);
    let result = call(state, move |session| session.logout(all)).await;
    if result.is_ok() {
        clear_snapshot_previews(&previews);
    }
    result
}

#[tauri::command]
pub async fn account_delete(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    let previews = Arc::clone(&state.snapshot_previews);
    let result = call(state, |session| session.delete_account()).await;
    if result.is_ok() {
        clear_snapshot_previews(&previews);
    }
    result
}

#[tauri::command]
pub async fn account_forget(state: State<'_, AccountState>) -> Result<(), super::CommandError> {
    let previews = Arc::clone(&state.snapshot_previews);
    let result = call(state, |session| session.forget()).await;
    if result.is_ok() {
        clear_snapshot_previews(&previews);
    }
    result
}

pub async fn cloud_clipboard_request(
    state: State<'_, AccountState>,
    action: Value,
) -> Result<Value, super::CommandError> {
    let operation = action
        .get("operation")
        .and_then(Value::as_str)
        .ok_or(super::CommandError {
            code: "invalid_cloud_clipboard",
        })?;
    match operation {
        "list" => {
            let search = action
                .get("search")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .to_owned();
            call(state, move |session| {
                session.clipboard(&search).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        "set_enabled" => {
            let enabled = action
                .get("enabled")
                .and_then(Value::as_bool)
                .ok_or(super::CommandError {
                    code: "invalid_cloud_clipboard",
                })?;
            call(state, move |session| {
                session
                    .set_clipboard_enabled(enabled)
                    .map(|()| serde_json::json!({ "enabled": enabled }))
            })
            .await
        }
        "add" => {
            let text = action
                .get("text")
                .and_then(Value::as_str)
                .ok_or(super::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(state, move |session| {
                session.add_clipboard(&text).and_then(|item| {
                    serde_json::to_value(item).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        "delete" => {
            let id = action
                .get("id")
                .and_then(Value::as_str)
                .ok_or(super::CommandError {
                    code: "invalid_cloud_clipboard",
                })?
                .to_owned();
            call(state, move |session| {
                session
                    .delete_clipboard(Some(&id))
                    .map(|()| serde_json::json!({}))
            })
            .await
        }
        _ => Err(super::CommandError {
            code: "invalid_cloud_clipboard",
        }),
    }
}

fn dictionary_kind(value: &str) -> Result<DictionaryKind, super::CommandError> {
    match value {
        "pinyin" => Ok(DictionaryKind::Pinyin),
        "wubi" => Ok(DictionaryKind::Wubi),
        "quick" => Ok(DictionaryKind::Quick),
        "english" => Ok(DictionaryKind::English),
        _ => Err(super::CommandError {
            code: "invalid_cloud_dictionary",
        }),
    }
}

pub async fn cloud_dictionary_request(
    state: State<'_, AccountState>,
    action: Value,
) -> Result<Value, super::CommandError> {
    use msime_host_api::cloud_dictionary::CloudDictionaryRequest;

    let request: CloudDictionaryRequest =
        serde_json::from_value(action).map_err(|_| super::CommandError {
            code: "invalid_cloud_dictionary",
        })?;
    match request {
        CloudDictionaryRequest::SnapshotPreview => dictionary_snapshot_preview(state).await,
        CloudDictionaryRequest::SnapshotExport => dictionary_snapshot_export(state).await,
        CloudDictionaryRequest::SnapshotRestorePreview { text } => {
            dictionary_snapshot_restore_preview(state, text).await
        }
        CloudDictionaryRequest::SnapshotRestore {
            text,
            expected_sha256,
            revision,
        } => dictionary_snapshot_restore(state, text, expected_sha256, revision).await,
        CloudDictionaryRequest::SnapshotEnqueue { token } => {
            dictionary_snapshot_enqueue(state, token).await
        }
        CloudDictionaryRequest::SnapshotStatus => dictionary_snapshot_status(state).await,
        CloudDictionaryRequest::SnapshotCancel => dictionary_snapshot_cancel(state).await,
        CloudDictionaryRequest::List {
            kind,
            offset,
            search,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session.dictionary(kind, &search, offset).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::Catalog {
            kind,
            code,
            offset,
            scheme,
            profile,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .dictionary_catalog(kind, &code, offset, &scheme, &profile)
                    .and_then(|page| {
                        serde_json::to_value(serde_json::json!({
                            "catalog_entries": page.entries,
                            "has_more": page.has_more,
                            "offset": page.offset,
                            "revision": page.revision,
                            "normalized": page.normalized,
                        }))
                        .map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Add {
            kind,
            code,
            word,
            weight,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .add_dictionary(kind, &code, &word, weight)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Update {
            kind,
            id,
            code,
            word,
            weight,
            revision,
        } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .update_dictionary(kind, &id, &code, &word, weight, revision)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::EditCatalog {
            kind,
            code,
            word,
            revision,
            replacement,
        } => {
            let kind = dictionary_kind(&kind)?;
            let replacement = replacement.map(|value| (value.code, value.word, value.weight));
            call(state, move |session| {
                let replacement = replacement
                    .as_ref()
                    .map(|(code, word, weight)| (code.as_str(), word.as_str(), *weight));
                session
                    .edit_dictionary_catalog(kind, &code, &word, revision, replacement)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Candidates {
            text,
            kind,
            scheme,
            profile,
            limit,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| {
                session.personal_candidates(&query).and_then(|result| {
                    serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::Rank {
            text,
            kind,
            scheme,
            profile,
            limit,
            code,
            word,
            revision,
            mode,
            linear_step,
            trigger_count,
            force_top,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| {
                session
                    .rank_candidate(
                        &query,
                        &code,
                        &word,
                        revision,
                        &mode,
                        linear_step,
                        trigger_count,
                        force_top,
                    )
                    .map(|result| {
                        serde_json::json!({
                            "revision": result.revision,
                            "changed": result.changed,
                            "selection_count": result.selection.count,
                        })
                    })
            })
            .await
        }
        CloudDictionaryRequest::RemoveCandidate {
            text,
            kind,
            scheme,
            profile,
            limit,
            code,
            word,
            revision,
        } => {
            let query = AccountCandidateQuery {
                text,
                kind,
                scheme,
                profile,
                limit,
            };
            call(state, move |session| {
                session
                    .remove_candidate(&query, &code, &word, revision)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::FixedPositions { context, offset } => {
            call(state, move |session| {
                session.fixed_positions(&context, offset).and_then(|result| {
                    serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
        CloudDictionaryRequest::SetFixedPosition {
            context,
            code,
            word,
            position,
            revision,
        } => {
            call(state, move |session| {
                session
                    .set_fixed_position(&context, &code, &word, position, revision)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Delete { kind, id, revision } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .delete_dictionary(kind, &id, revision)
                    .and_then(|change| {
                        serde_json::to_value(change).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Import { kind, format, text } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session
                    .import_dictionary(kind, &format, &text)
                    .and_then(|result| {
                        serde_json::to_value(result).map_err(|_| AccountError::Unavailable)
                    })
            })
            .await
        }
        CloudDictionaryRequest::Export { kind, format } => {
            let kind = dictionary_kind(&kind)?;
            call(state, move |session| {
                session.export_dictionary(kind, &format).map(|result| {
                    serde_json::json!({
                        "text": result.text,
                        "filename": result.filename,
                    })
                })
            })
            .await
        }
        CloudDictionaryRequest::Changes { after, limit } => {
            call(state, move |session| {
                session.dictionary_changes(after, limit).and_then(|page| {
                    serde_json::to_value(page).map_err(|_| AccountError::Unavailable)
                })
            })
            .await
        }
    }
}

#[tauri::command]
pub async fn app_icon_info(
    state: State<'_, AccountState>,
) -> Result<AppIconResponse, super::CommandError> {
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<AppIconResponse>("appIconInfo", ())
            .map_err(|_| super::CommandError { code: "app_icon" })
    })
    .await
    .map_err(|_| super::CommandError { code: "app_icon" })?
}

#[tauri::command]
pub async fn app_icon_set(
    state: State<'_, AccountState>,
    style: String,
) -> Result<AppIconResponse, super::CommandError> {
    if !matches!(style.as_str(), "classic" | "forest" | "sky" | "dusk" | "vermilion") {
        return Err(super::CommandError {
            code: "invalid_app_icon",
        });
    }
    let plugin = state.platform.clone();
    tauri::async_runtime::spawn_blocking(move || {
        plugin
            .run_mobile_plugin::<AppIconResponse>("setAppIcon", AppIconRequest { style: &style })
            .map_err(|_| super::CommandError { code: "app_icon" })
    })
    .await
    .map_err(|_| super::CommandError { code: "app_icon" })?
}

fn insert_string(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: &str) {
    settings.insert(
        key.to_owned(),
        AccountPreferenceValue::String(value.to_owned()),
    );
}

fn insert_bool(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: bool) {
    settings.insert(key.to_owned(), AccountPreferenceValue::Boolean(value));
}

fn insert_integer(settings: &mut BTreeMap<String, AccountPreferenceValue>, key: &str, value: i64) {
    settings.insert(key.to_owned(), AccountPreferenceValue::Integer(value));
}

fn local_account_preferences(
    snapshot: &PreferencesSnapshot,
    feedback: &PluginHandle<Wry>,
) -> Result<BTreeMap<String, AccountPreferenceValue>, AccountError> {
    let preferences = &snapshot.preferences;
    let mut settings = BTreeMap::new();
    insert_string(
        &mut settings,
        "input.schema",
        match preferences.scheme {
            InputScheme::Quanpin => "quanpin",
            InputScheme::Shuangpin => "shuangpin",
            InputScheme::Wubi => "wubi",
            InputScheme::Japanese => "japanese",
        },
    );
    insert_string(
        &mut settings,
        "input.character_set",
        if preferences.traditional_chinese_output {
            "traditional"
        } else {
            "simplified"
        },
    );
    insert_string(
        &mut settings,
        "input.shuangpin_schema",
        match preferences.shuangpin_profile {
            ShuangpinProfile::Xiaohe => "xiaohe",
            ShuangpinProfile::Ziranma => "ziranma",
            ShuangpinProfile::Shoudao => "shoudao",
            ShuangpinProfile::Microsoft => "microsoft",
        },
    );
    insert_bool(&mut settings, "input.learning", preferences.learning);
    insert_bool(
        &mut settings,
        "input.chinese_punctuation",
        preferences.chinese_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.smart_punctuation",
        preferences.smart_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.paired_punctuation",
        preferences.paired_punctuation,
    );
    insert_bool(
        &mut settings,
        "input.wubi_code_hint",
        preferences.wubi_code_hint.unwrap_or(true),
    );
    insert_string(
        &mut settings,
        "platform.android.keyboard_layout",
        match preferences.touch_keyboard_layout {
            TouchKeyboardLayout::TwentySixKey => "twenty_six_key",
            TouchKeyboardLayout::NineKey => "nine_key",
            TouchKeyboardLayout::Handwriting => "handwriting",
        },
    );
    insert_string(
        &mut settings,
        "platform.android.keyboard_skin",
        match preferences.touch_keyboard_skin {
            TouchKeyboardSkin::Forest => "forest",
            TouchKeyboardSkin::Ocean => "ocean",
            TouchKeyboardSkin::Rose => "rose",
            TouchKeyboardSkin::Porcelain => "porcelain",
            TouchKeyboardSkin::Typewriter => "typewriter",
            TouchKeyboardSkin::Candy => "candy",
            TouchKeyboardSkin::Midnight => "midnight",
            TouchKeyboardSkin::Blueprint => "blueprint",
            TouchKeyboardSkin::Custom => "custom",
        },
    );
    let custom_skin = serde_json::to_string(&preferences.custom_touch_keyboard_skin)
        .map_err(|_| AccountError::Invalid)?;
    insert_string(
        &mut settings,
        "platform.android.custom_keyboard_skin",
        &custom_skin,
    );
    insert_string(
        &mut settings,
        "platform.android.theme",
        match preferences.theme {
            ThemeMode::Dark => "dark",
            ThemeMode::Light => "light",
            ThemeMode::System => "system",
        },
    );
    insert_string(
        &mut settings,
        "platform.android.candidate_skin",
        &preferences.candidate_skin,
    );
    insert_integer(
        &mut settings,
        "platform.android.touch_key_spacing_tenths",
        i64::from(preferences.touch_key_spacing_tenths),
    );
    insert_integer(
        &mut settings,
        "platform.android.touch_row_spacing_tenths",
        i64::from(preferences.touch_row_spacing_tenths),
    );
    insert_integer(
        &mut settings,
        "platform.android.keyboard_height_adjustment",
        i64::from(preferences.touch_keyboard_height_adjustment),
    );
    insert_bool(
        &mut settings,
        "platform.android.voice_shortcut",
        preferences.touch_voice_shortcut,
    );

    let feedback = feedback
        .run_mobile_plugin::<FeedbackSettings>("loadFeedback", ())
        .map_err(|_| AccountError::Storage)?;
    insert_bool(
        &mut settings,
        "platform.android.sound_enabled",
        feedback.sound_enabled,
    );
    insert_bool(
        &mut settings,
        "platform.android.haptics_enabled",
        feedback.haptics_enabled,
    );
    insert_string(
        &mut settings,
        "platform.android.haptic_strength",
        &feedback.haptic_strength,
    );
    Ok(settings)
}

fn string_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<String>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::String(value)) => Ok(Some(value.clone())),
        Some(_) => Ok(None),
    }
}

fn bool_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<bool>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::Boolean(value)) => Ok(Some(*value)),
        Some(_) => Ok(None),
    }
}

fn integer_setting(
    settings: &BTreeMap<String, AccountPreferenceValue>,
    key: &str,
) -> Result<Option<i64>, AccountError> {
    match settings.get(key) {
        None => Ok(None),
        Some(AccountPreferenceValue::Integer(value)) => Ok(Some(*value)),
        Some(AccountPreferenceValue::Number(value)) if value.is_finite() => {
            if value.fract() == 0.0 {
                Ok(Some(*value as i64))
            } else {
                Err(AccountError::Invalid)
            }
        }
        Some(_) => Ok(None),
    }
}

fn apply_local_account_preferences(
    snapshot: &PreferencesSnapshot,
    cloud: &AccountPreferences,
    schema: &AccountPreferenceSchema,
    feedback: &PluginHandle<Wry>,
) -> Result<Preferences, AccountError> {
    validate_account_preferences(cloud)?;
    for (key, value) in &cloud.settings {
        if let Some(field) = schema.fields.get(key) {
            if field.value_type != value.kind()
                && !(field.value_type == "number" && value.kind() == "integer")
            {
                return Err(AccountError::Invalid);
            }
        }
    }
    let mut preferences = snapshot.preferences.clone();
    let values = &cloud.settings;
    let supports = |key: &str, expected: &str| -> Result<bool, AccountError> {
        match schema.fields.get(key) {
            None => Ok(false),
            Some(field)
                if field.value_type == expected
                    || ((expected == "number" || expected == "integer")
                        && matches!(field.value_type.as_str(), "integer" | "number")) =>
            {
                Ok(true)
            }
            Some(_) => Err(AccountError::Invalid),
        }
    };
    if let Some(value) = string_setting(values, "input.schema")? {
        if supports("input.schema", "string")? {
            preferences.scheme = match value.as_str() {
                "quanpin" => InputScheme::Quanpin,
                "shuangpin" => InputScheme::Shuangpin,
                "wubi" => InputScheme::Wubi,
                "japanese" => InputScheme::Japanese,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "input.character_set")? {
        if supports("input.character_set", "string")? {
            preferences.traditional_chinese_output = match value.as_str() {
                "traditional" => true,
                "simplified" => false,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "input.shuangpin_schema")? {
        if supports("input.shuangpin_schema", "string")? {
            preferences.shuangpin_profile = match value.as_str() {
                "xiaohe" => ShuangpinProfile::Xiaohe,
                "ziranma" => ShuangpinProfile::Ziranma,
                "shoudao" => ShuangpinProfile::Shoudao,
                "microsoft" => ShuangpinProfile::Microsoft,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = bool_setting(values, "input.learning")? {
        if supports("input.learning", "boolean")? {
            preferences.learning = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.chinese_punctuation")? {
        if supports("input.chinese_punctuation", "boolean")? {
            preferences.chinese_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.smart_punctuation")? {
        if supports("input.smart_punctuation", "boolean")? {
            preferences.smart_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.paired_punctuation")? {
        if supports("input.paired_punctuation", "boolean")? {
            preferences.paired_punctuation = value;
        }
    }
    if let Some(value) = bool_setting(values, "input.wubi_code_hint")? {
        if supports("input.wubi_code_hint", "boolean")? {
            preferences.wubi_code_hint = Some(value);
        }
    }
    if let Some(value) = string_setting(values, "platform.android.keyboard_layout")? {
        if supports("platform.android.keyboard_layout", "string")? {
            preferences.touch_keyboard_layout = match value.as_str() {
                "twenty_six_key" => TouchKeyboardLayout::TwentySixKey,
                "nine_key" => TouchKeyboardLayout::NineKey,
                "handwriting" => TouchKeyboardLayout::Handwriting,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.keyboard_skin")? {
        if supports("platform.android.keyboard_skin", "string")? {
            preferences.touch_keyboard_skin = match value.as_str() {
                "forest" => TouchKeyboardSkin::Forest,
                "ocean" => TouchKeyboardSkin::Ocean,
                "rose" => TouchKeyboardSkin::Rose,
                "porcelain" => TouchKeyboardSkin::Porcelain,
                "typewriter" => TouchKeyboardSkin::Typewriter,
                "candy" => TouchKeyboardSkin::Candy,
                "midnight" => TouchKeyboardSkin::Midnight,
                "blueprint" => TouchKeyboardSkin::Blueprint,
                "custom" => TouchKeyboardSkin::Custom,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.custom_keyboard_skin")? {
        if supports("platform.android.custom_keyboard_skin", "string")? {
            preferences.custom_touch_keyboard_skin =
                serde_json::from_str(&value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = string_setting(values, "platform.android.theme")? {
        if supports("platform.android.theme", "string")? {
            preferences.theme = match value.as_str() {
                "dark" => ThemeMode::Dark,
                "light" => ThemeMode::Light,
                "system" => ThemeMode::System,
                _ => return Err(AccountError::Invalid),
            };
        }
    }
    if let Some(value) = string_setting(values, "platform.android.candidate_skin")? {
        if supports("platform.android.candidate_skin", "string")? {
            if value.is_empty() || value.len() > 128 || value.chars().any(char::is_control) {
                return Err(AccountError::Invalid);
            }
            preferences.candidate_skin = value;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.touch_key_spacing_tenths")? {
        if supports("platform.android.touch_key_spacing_tenths", "integer")? {
            preferences.touch_key_spacing_tenths =
                u8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.touch_row_spacing_tenths")? {
        if supports("platform.android.touch_row_spacing_tenths", "integer")? {
            preferences.touch_row_spacing_tenths =
                u8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = integer_setting(values, "platform.android.keyboard_height_adjustment")? {
        if supports("platform.android.keyboard_height_adjustment", "integer")? {
            preferences.touch_keyboard_height_adjustment =
                i8::try_from(value).map_err(|_| AccountError::Invalid)?;
        }
    }
    if let Some(value) = bool_setting(values, "platform.android.voice_shortcut")? {
        if supports("platform.android.voice_shortcut", "boolean")? {
            preferences.touch_voice_shortcut = value;
        }
    }

    let feedback_keys = [
        "platform.android.sound_enabled",
        "platform.android.haptics_enabled",
        "platform.android.haptic_strength",
    ];
    let mut feedback_values = if feedback_keys
        .iter()
        .any(|key| schema.fields.contains_key(*key) && values.contains_key(*key))
    {
        Some(
            feedback
                .run_mobile_plugin::<FeedbackSettings>("loadFeedback", ())
                .map_err(|_| AccountError::Storage)?,
        )
    } else {
        None
    };
    if let Some(value) = bool_setting(values, "platform.android.sound_enabled")? {
        if supports("platform.android.sound_enabled", "boolean")? {
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .sound_enabled = value;
        }
    }
    if let Some(value) = bool_setting(values, "platform.android.haptics_enabled")? {
        if supports("platform.android.haptics_enabled", "boolean")? {
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .haptics_enabled = value;
        }
    }
    if let Some(value) = string_setting(values, "platform.android.haptic_strength")? {
        if supports("platform.android.haptic_strength", "string")? {
            if !matches!(value.as_str(), "light" | "medium" | "strong") {
                return Err(AccountError::Invalid);
            }
            feedback_values
                .as_mut()
                .ok_or(AccountError::Storage)?
                .haptic_strength = value;
        }
    }
    if let Some(feedback_values) = feedback_values {
        let request = serde_json::json!({
            "soundEnabled": feedback_values.sound_enabled,
            "hapticsEnabled": feedback_values.haptics_enabled,
            "hapticStrength": feedback_values.haptic_strength,
        });
        feedback
            .run_mobile_plugin::<()>("saveFeedback", request)
            .map_err(|_| AccountError::Storage)?;
    }
    preferences.validate().map_err(|_| AccountError::Invalid)?;
    Ok(preferences)
}

#[tauri::command]
pub async fn account_preferences_schema(
    state: State<'_, AccountState>,
) -> Result<PreferenceSchemaResponse, super::CommandError> {
    call(state, |session| session.preference_schema().map(Into::into)).await
}

#[tauri::command]
pub async fn account_preferences_load(
    state: State<'_, AccountState>,
) -> Result<AccountPreferences, super::CommandError> {
    call(state, |session| session.preferences()).await
}

#[tauri::command]
pub async fn account_preferences_upload(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
) -> Result<AccountPreferences, super::CommandError> {
    let session = Arc::clone(&state.session);
    let feedback = state.feedback.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let schema = session.preference_schema()?;
        let cloud = session.preferences()?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let values = local_account_preferences(&local, &feedback)?
            .into_iter()
            .filter(|(key, _)| schema.fields.contains_key(key))
            .collect::<BTreeMap<_, _>>();
        if values.is_empty() {
            return Err(AccountError::Unavailable);
        }
        let merged = merge_account_preferences(&cloud, &values, &schema)?;
        session.put_preferences(&merged)
    })
    .await
    .map_err(|_| super::CommandError { code: "account_unavailable" })?
    .map_err(|error| super::CommandError { code: error.code() })
}

#[tauri::command]
pub async fn account_preferences_apply(
    state: State<'_, AccountState>,
    store: State<'_, Arc<PreferencesStore>>,
    user_id: String,
    preferences: AccountPreferences,
) -> Result<(), super::CommandError> {
    let session = Arc::clone(&state.session);
    let feedback = state.feedback.clone();
    let store = store.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        session.credentials(None, Some(&user_id))?;
        let schema = session.preference_schema()?;
        let local = store.load().map_err(|_| AccountError::Storage)?;
        let next = apply_local_account_preferences(&local, &preferences, &schema, &feedback)?;
        store
            .save(local.revision, next)
            .map_err(|_| AccountError::Storage)?;
        Ok::<(), AccountError>(())
    })
    .await
    .map_err(|_| super::CommandError { code: "account_unavailable" })?
    .map_err(|error| super::CommandError { code: error.code() })
}

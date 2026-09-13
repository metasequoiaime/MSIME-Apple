//! Native management requests. The native caller owns and authorizes all paths.

use super::{edit_personal_dictionary, response, DictionaryAccess, HostOptions};
use msime_client_core::personal_dictionary::{
    PersonalDictionaryError, PersonalDictionaryStore, PersonalWord, PersonalWordKind,
    PersonalWordRequestStatus,
};
use msime_engine_bridge::{DictionaryEntry, DictionaryKind};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::ffi::c_char;
use std::path::Path;

#[derive(Clone, Copy, Deserialize, Serialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
enum Kind {
    Pinyin,
    Wubi,
    QuickPhrase,
    English,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Entry {
    kind: Kind,
    key: String,
    value: String,
    weight: i64,
}

impl From<Entry> for DictionaryEntry {
    fn from(entry: Entry) -> Self {
        Self {
            kind: match entry.kind {
                Kind::Pinyin => DictionaryKind::Pinyin,
                Kind::Wubi => DictionaryKind::Wubi,
                Kind::QuickPhrase => DictionaryKind::QuickPhrase,
                Kind::English => DictionaryKind::English,
            },
            key: entry.key,
            value: entry.value,
            weight: entry.weight,
        }
    }
}

impl From<Kind> for msime_engine_bridge::DictionaryKind {
    fn from(kind: Kind) -> Self {
        match kind {
            Kind::Pinyin => Self::Pinyin,
            Kind::Wubi => Self::Wubi,
            Kind::QuickPhrase => Self::QuickPhrase,
            Kind::English => Self::English,
        }
    }
}

impl TryFrom<DictionaryEntry> for Entry {
    type Error = &'static str;

    fn try_from(entry: DictionaryEntry) -> Result<Self, Self::Error> {
        let kind = match entry.kind {
            DictionaryKind::Pinyin => Kind::Pinyin,
            DictionaryKind::Wubi => Kind::Wubi,
            DictionaryKind::QuickPhrase => Kind::QuickPhrase,
            DictionaryKind::English => Kind::English,
            _ => return Err("unsupported dictionary kind"),
        };
        Ok(Self {
            kind,
            key: entry.key,
            value: entry.value,
            weight: entry.weight,
        })
    }
}

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Operation {
    List {
        offset: usize,
        limit: usize,
    },
    Edit {
        previous: Option<Entry>,
        replacement: Option<Entry>,
        request_id: String,
    },
    Import {
        kind: Kind,
        format: String,
        text: String,
        request_id: String,
    },
    ImportPersonal {
        text: String,
        request_id: String,
    },
    Export {
        kind: Kind,
        format: String,
        offset: usize,
        limit: usize,
    },
    Retry {
        request_id: String,
    },
    DismissFailure {
        request_id: String,
    },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    options: HostOptions,
    action: Operation,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PersonalDictionaryImport {
    format: String,
    version: u32,
    entries: Vec<PersonalWord>,
}

fn parse_personal_dictionary_import(text: &str) -> Result<Vec<PersonalWord>, String> {
    if text.len() > 1_048_576 {
        return Err("personal dictionary file is too large".into());
    }
    let file: PersonalDictionaryImport =
        serde_json::from_str(text).map_err(|_| "invalid personal dictionary file".to_owned())?;
    if file.format != "msime-personal-dictionary" || file.version != 1 {
        return Err("unsupported personal dictionary file".into());
    }
    if file.entries.is_empty() || file.entries.len() > 128 {
        return Err("invalid personal dictionary entry count".into());
    }
    let mut identities = std::collections::HashSet::new();
    for entry in &file.entries {
        entry
            .validate()
            .map_err(|_| "invalid personal dictionary entry".to_owned())?;
        if !identities.insert(entry.identity()) {
            return Err("duplicate personal dictionary entry".into());
        }
    }
    Ok(file.entries)
}

/// Native management requests return only redacted errors.
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary(request: *const u8, length: usize) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        dictionary_request_json(bytes)
    })
}

pub fn dictionary_request_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    if bytes.len() > 65536 {
        return Err("invalid dictionary buffer".into());
    }
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request".to_owned())?;
    if request.options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    request
        .options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options".to_owned())?;
    let options = request.options.into_engine_options();
    match request.action {
        Operation::List { offset, limit } => {
            let _access = DictionaryAccess::try_session(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let page = msime_engine_bridge::dictionary_entries(&options, offset, limit)
                .map_err(|_| "dictionary read rejected")?;
            let entries: Vec<Entry> = page
                .entries
                .into_iter()
                .map(Entry::try_from)
                .collect::<Result<_, _>>()?;
            Ok(json!({ "entries": entries, "has_more": page.has_more }))
        }
        Operation::Edit {
            previous,
            replacement,
            request_id,
        } => {
            for entry in previous.iter().chain(replacement.iter()) { validate_entry(entry)?; }
            let previous = previous.map(DictionaryEntry::from);
            let replacement = replacement.map(DictionaryEntry::from);
            edit_personal_dictionary(
                &options,
                previous.as_ref(),
                replacement.as_ref(),
                &request_id,
            )?;
            Ok(json!({ "applied": true }))
        }
        Operation::Import {
            kind,
            format,
            text,
            request_id,
        } => {
            let (entries, report) = if format == "hans" {
                (parse_hans_import(&kind, &text, &options)?, None)
            } else {
                let (entries, report) = parse_import(&kind, &format, &text, Some(&options))?;
                (entries, Some(report))
            };
            if request_id.is_empty()
                || request_id.len() > 120
                || !request_id
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            {
                return Err("invalid dictionary request ID".into());
            }
            let _access = DictionaryAccess::try_maintenance(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let mut applied = 0usize;
            for (index, entry) in entries.iter().enumerate() {
                let receipt = format!("{request_id}-{index}");
                // The batch already owns the maintenance lock; use the Engine bridge directly.
                let result =
                    msime_engine_bridge::dictionary_edit(&options, None, Some(entry), &receipt);
                if result.is_err() {
                    return Err("dictionary import rejected".into());
                }
                applied += 1;
            }
            let mut result = json!({ "applied": applied });
            // Tell the caller what was skipped instead of reporting a clean import.
            if let Some(report) = report {
                result["failed"] = json!(report.failed);
                result["truncated"] = json!(report.truncated);
                result["first_failures"] = serde_json::to_value(&report.first_failures)
                    .map_err(|error| error.to_string())?;
            }
            Ok(result)
        }
        Operation::ImportPersonal { .. } => {
            Err("personal dictionary import requires the Android queue".into())
        }
        Operation::Export {
            kind,
            format,
            offset,
            limit,
        } => {
            if !matches!(format.as_str(), "standard" | "windows")
                || offset > 1_000_000
                || !(1..=1000).contains(&limit)
            {
                return Err("invalid dictionary export".into());
            }
            let _access = DictionaryAccess::try_session(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let mut cursor = 0usize;
            let mut matching = Vec::new();
            let mut source_has_more = true;
            while source_has_more && matching.len() < offset.saturating_add(limit) {
                let page = msime_engine_bridge::dictionary_entries(&options, cursor, 1000)
                    .map_err(|_| "dictionary read rejected")?;
                if page.entries.is_empty() {
                    source_has_more = false;
                    break;
                }
                cursor = cursor.saturating_add(page.entries.len());
                source_has_more = page.has_more;
                matching.extend(
                    page.entries
                        .into_iter()
                        .filter(|entry| entry.kind == kind.into()),
                );
                if cursor > 1_000_000 {
                    break;
                }
            }
            let has_more = matching.len() > offset.saturating_add(limit)
                || (source_has_more && matching.len() >= offset.saturating_add(limit));
            let text = matching
                .into_iter()
                .skip(offset)
                .take(limit)
                .map(|entry| {
                    if format == "windows" {
                        format!("{}\t{}\t{}", entry.key, entry.value, entry.weight)
                    } else {
                        format!("{}\t{}\t{}", entry.value, entry.key, entry.weight)
                    }
                })
                .collect::<Vec<_>>()
                .join("\n");
            let text = if text.is_empty() {
                text
            } else {
                format!("{text}\n")
            };
            Ok(json!({ "text": text, "has_more": has_more }))
        }
        Operation::Retry { .. } | Operation::DismissFailure { .. } => {
            Err("dictionary failure actions require the Android personal dictionary API".into())
        }
    }
}

/// Android settings use a shared host/keyboard queue rather than editing the
/// Engine while the IME may still own a session. The queue is intentionally a
/// separate entry point so desktop hosts retain their synchronous contract.
pub fn personal_dictionary_request_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    // JSON imports are bounded by the Apple-compatible 1 MiB file limit; the
    // small amount of request framing needs room in addition to the file.
    if bytes.len() > 1_200_000 {
        return Err("invalid dictionary buffer".into());
    }
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request".to_owned())?;
    if request.options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    request
        .options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options".to_owned())?;
    let directory = request
        .options
        .preferences_directory
        .as_deref()
        .filter(|path| Path::new(path).is_absolute())
        .ok_or("personal dictionary shared directory unavailable")?;
    let store = PersonalDictionaryStore::new(Path::new(directory).join("PersonalDictionary"));
    match request.action {
        Operation::List { offset, limit } => {
            if offset > 1_000_000 || !(1..=1000).contains(&limit) {
                return Err("invalid dictionary page".into());
            }
            store
                .request_page(offset)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            let has_more = state.has_more;
            let pending_count = state.pending_count();
            let snapshot_date = state.snapshot_date.clone();
            let snapshot_error = state.snapshot_error.clone();
            let page_offset = state.page_offset;
            let requested_page_offset = state.requested_page_offset;
            let failed_requests: Vec<_> = state
                .requests
                .iter()
                .filter(|request| request.status == PersonalWordRequestStatus::Failed)
                .map(|request| {
                    json!({
                        "request_id": request.id,
                        "label": request.replacement.as_ref()
                            .or(request.previous.as_ref())
                            .map(|word| word.value.clone())
                            .unwrap_or_else(|| "词条".to_owned()),
                        "error": request.error.as_deref().unwrap_or("同步失败"),
                    })
                })
                .collect();
            let entries = state
                .entries
                .into_iter()
                .map(personal_to_entry)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(json!({
                "entries": entries,
                "has_more": has_more,
                "pending_count": pending_count,
                "snapshot_date": snapshot_date,
                "snapshot_error": snapshot_error,
                "page_offset": page_offset,
                "requested_page_offset": requested_page_offset,
                "failed_requests": failed_requests,
            }))
        }
        Operation::Edit {
            previous,
            replacement,
            request_id,
        } => {
            let previous = previous.map(personal_from_entry).transpose()?;
            let replacement = replacement.map(personal_from_entry).transpose()?;
            store
                .enqueue(previous, replacement, request_id)
                .map_err(personal_dictionary_error)?;
            let pending_count = store
                .read()
                .map_err(personal_dictionary_error)?
                .pending_count();
            Ok(json!({ "queued": true, "pending_count": pending_count }))
        }
        Operation::Import {
            kind,
            format,
            text,
            request_id,
        } => {
            let options = request.options.into_engine_options();
            let entries = if format == "hans" {
                parse_hans_import(&kind, &text, &options)?
            } else {
                parse_import(&kind, &format, &text, Some(&options))?.0
            };
            let words = entries
                .into_iter()
                .map(|entry| {
                    PersonalWord {
                        kind: personal_kind(entry.kind),
                        key: entry.key,
                        value: entry.value,
                        weight: entry.weight,
                    }
                })
                .collect();
            store
                .enqueue_import(words, request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "queued": true, "pending_count": state.pending_count() }))
        }
        Operation::ImportPersonal { text, request_id } => {
            let entries = parse_personal_dictionary_import(&text)?;
            store
                .enqueue_import(entries, request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "queued": true, "pending_count": state.pending_count() }))
        }
        Operation::Export {
            kind,
            format,
            offset,
            limit,
        } => {
            if !matches!(format.as_str(), "standard" | "windows")
                || offset > 1_000_000
                || !(1..=1000).contains(&limit)
            {
                return Err("invalid dictionary export".into());
            }
            let state = store.read().map_err(personal_dictionary_error)?;
            let matching: Vec<_> = state
                .entries
                .into_iter()
                .filter(|entry| personal_to_kind(entry.kind) == kind)
                .collect();
            let has_more = matching.len() > offset.saturating_add(limit);
            let text = matching
                .into_iter()
                .skip(offset)
                .take(limit)
                .map(|entry| {
                    if format == "windows" {
                        format!("{}\t{}\t{}", entry.key, entry.value, entry.weight)
                    } else {
                        format!("{}\t{}\t{}", entry.value, entry.key, entry.weight)
                    }
                })
                .collect::<Vec<_>>()
                .join("\n");
            let text = if text.is_empty() {
                text
            } else {
                format!("{text}\n")
            };
            Ok(json!({ "text": text, "has_more": has_more }))
        }
        Operation::Retry { request_id } => {
            store
                .retry(&request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "pending_count": state.pending_count() }))
        }
        Operation::DismissFailure { request_id } => {
            store
                .dismiss_failure(&request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "pending_count": state.pending_count() }))
        }
    }
}

/// Synchronize the Android queue with the Engine. The caller must invoke this
/// only after its Engine session has been destroyed; the shared dictionary lock
/// then prevents races with any other host.
pub fn personal_dictionary_sync_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    if bytes.len() > 65536 {
        return Err("invalid dictionary buffer".into());
    }
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request".to_owned())?;
    if request.options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    request
        .options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options".to_owned())?;
    let directory = request
        .options
        .preferences_directory
        .as_deref()
        .filter(|path| Path::new(path).is_absolute())
        .ok_or("personal dictionary shared directory unavailable")?;
    let store = PersonalDictionaryStore::new(Path::new(directory).join("PersonalDictionary"));
    let options = request.options.into_engine_options();
    store
        .synchronize(
            |queued| {
                let previous = queued.previous.as_ref().map(personal_engine_entry);
                let replacement = queued.replacement.as_ref().map(personal_engine_entry);
                edit_personal_dictionary(
                    &options,
                    previous.as_ref(),
                    replacement.as_ref(),
                    &queued.id,
                )
                .map_err(str::to_owned)
            },
            |offset| {
                let page = msime_engine_bridge::dictionary_entries(&options, offset, 100)
                    .map_err(|_| "dictionary read rejected".to_owned())?;
                Ok(msime_client_core::personal_dictionary::PersonalWordPage {
                    entries: page
                        .entries
                        .into_iter()
                        .map(|entry| PersonalWord {
                            kind: personal_kind(entry.kind),
                            key: entry.key,
                            value: entry.value,
                            weight: entry.weight,
                        })
                        .collect(),
                    has_more: page.has_more,
                })
            },
        )
        .map_err(personal_dictionary_error)?;
    let state = store.read().map_err(personal_dictionary_error)?;
    Ok(json!({
        "synchronized": true,
        "pending_count": state.pending_count(),
        "snapshot_error": state.snapshot_error,
    }))
}

/// JNI entry point for the Android IME worker.
///
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_personal_dictionary_sync(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        personal_dictionary_sync_json(bytes)
    })
}

fn personal_dictionary_error(error: PersonalDictionaryError) -> String {
    error.to_string()
}

fn personal_from_entry(entry: Entry) -> Result<PersonalWord, String> {
    validate_entry(&entry)?;
    Ok(PersonalWord {
        kind: personal_kind(entry.kind.into()),
        key: entry.key,
        value: entry.value,
        weight: entry.weight,
    })
}

fn personal_engine_entry(word: &PersonalWord) -> msime_engine_bridge::DictionaryEntry {
    msime_engine_bridge::DictionaryEntry {
        kind: match word.kind {
            PersonalWordKind::Pinyin => DictionaryKind::Pinyin,
            PersonalWordKind::Wubi => DictionaryKind::Wubi,
            PersonalWordKind::QuickPhrase => DictionaryKind::QuickPhrase,
            PersonalWordKind::English => DictionaryKind::English,
        },
        key: word.key.clone(),
        value: word.value.clone(),
        weight: word.weight,
    }
}

fn personal_to_entry(entry: PersonalWord) -> Result<Entry, String> {
    Ok(Entry {
        kind: personal_to_kind(entry.kind),
        key: entry.key,
        value: entry.value,
        weight: entry.weight,
    })
}

fn personal_kind(kind: DictionaryKind) -> PersonalWordKind {
    match kind {
        DictionaryKind::Pinyin => PersonalWordKind::Pinyin,
        DictionaryKind::Wubi => PersonalWordKind::Wubi,
        DictionaryKind::QuickPhrase => PersonalWordKind::QuickPhrase,
        DictionaryKind::English => PersonalWordKind::English,
        _ => unreachable!("unsupported personal dictionary kind"),
    }
}

fn personal_to_kind(kind: PersonalWordKind) -> Kind {
    match kind {
        PersonalWordKind::Pinyin => Kind::Pinyin,
        PersonalWordKind::Wubi => Kind::Wubi,
        PersonalWordKind::QuickPhrase => Kind::QuickPhrase,
        PersonalWordKind::English => Kind::English,
    }
}

fn validate_entry(entry: &Entry) -> Result<(), String> {
    let key_limit = match entry.kind { Kind::Pinyin => 256, Kind::Wubi => 4, Kind::QuickPhrase => 32, Kind::English => 64 };
    let key_valid = match entry.kind {
        Kind::Pinyin => entry.key.bytes().all(|b| b.is_ascii_lowercase() || b == b'\'' || b == b' '),
        Kind::Wubi | Kind::QuickPhrase => entry.key.bytes().all(|b| b.is_ascii_lowercase() || (matches!(entry.kind, Kind::QuickPhrase) && b.is_ascii_digit())),
        Kind::English => entry.key.bytes().all(|b| b.is_ascii_alphabetic()),
    };
    if entry.key.is_empty() || entry.key.len() > key_limit || !key_valid || entry.value.is_empty() || entry.value.chars().any(char::is_control) || entry.weight < 0 { return Err("invalid dictionary entry".into()); }
    if matches!(entry.kind, Kind::QuickPhrase) && entry.value.encode_utf16().count() > 199 { return Err("quick phrase too long".into()); }
    Ok(())
}

impl From<&Kind> for msime_client_core::dictionary_import::ImportKind {
    fn from(kind: &Kind) -> Self {
        use msime_client_core::dictionary_import::ImportKind;
        match kind {
            Kind::Pinyin => ImportKind::Pinyin,
            Kind::Wubi => ImportKind::Wubi,
            Kind::QuickPhrase => ImportKind::QuickPhrase,
            Kind::English => ImportKind::English,
        }
    }
}

/// Entries ready for the Engine, plus what the shared parser skipped.
type ParsedImport = (
    Vec<DictionaryEntry>,
    msime_client_core::dictionary_import::ImportReport,
);

/// Parse a submitted dictionary file through the shared parser. Unusable rows
/// are skipped and counted there rather than rejecting the whole file, so the
/// report is returned alongside the entries.
fn parse_import(
    kind: &Kind,
    format: &str,
    text: &str,
    engine_options: Option<&msime_engine_bridge::EngineOptions>,
) -> Result<ParsedImport, String> {
    let mut report = msime_client_core::dictionary_import::parse(
        kind.into(),
        format,
        text,
        msime_client_core::cloud_dictionary::MAX_IMPORT_BYTES,
    )
    .map_err(|error| error.to_string())?;
    if matches!(kind, Kind::Pinyin) && engine_options.is_some() {
        let mut usable = Vec::with_capacity(report.entries.len());
        for mut entry in report.entries.drain(..) {
            let expected_syllables = entry
                .value
                .chars()
                .filter(|&character| is_han_character(character))
                .count();
            let normalized = if (1..=128).contains(&expected_syllables) {
                msime_engine_bridge::normalize_full_pinyin(&entry.key, expected_syllables)
            } else {
                String::new()
            };
            if normalized.is_empty() {
                report.failed += 1;
                if report.first_failures.len() < 5 {
                    report.first_failures.push(
                        msime_client_core::dictionary_import::ImportFailure {
                            line: entry.line,
                            issue: msime_client_core::dictionary_import::ImportIssue::Pinyin,
                        },
                    );
                }
            } else {
                entry.key = normalized;
                usable.push(entry);
            }
        }
        report.entries = usable;
    }
    let entries = report
        .entries
        .iter()
        .map(|entry| DictionaryEntry {
            kind: (*kind).into(),
            key: entry.key.clone(),
            value: entry.value.clone(),
            weight: entry.weight,
        })
        .collect();
    Ok((entries, report))
}

fn parse_hans_import(
    kind: &Kind,
    text: &str,
    options: &msime_engine_bridge::EngineOptions,
) -> Result<Vec<DictionaryEntry>, String> {
    if !matches!(kind, Kind::Pinyin)
        || text.is_empty()
        || text.len() > msime_client_core::cloud_dictionary::MAX_IMPORT_BYTES
        || text.contains('\0')
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r'))
    {
        return Err("invalid dictionary import".into());
    }
    let mut entries = Vec::new();
    for line in text.lines() {
        let word = line.trim();
        if word.is_empty() || word.starts_with('#') {
            continue;
        }
        if entries.len() >= 1000 || word.len() > 1024 || !word.chars().all(is_han_character) {
            return Err("invalid dictionary import".into());
        }
        let key = msime_engine_bridge::hanzi_to_pinyin(options, word);
        if key.is_empty() || key.len() > 256 {
            return Err("dictionary pinyin unavailable".into());
        }
        entries.push(DictionaryEntry {
            kind: DictionaryKind::Pinyin,
            key,
            value: word.to_owned(),
            weight: 10000,
        });
    }
    if entries.is_empty() {
        return Err("invalid dictionary import".into());
    }
    Ok(entries)
}

fn is_han_character(character: char) -> bool {
    matches!(
        character as u32,
        0x3400..=0x4dbf
            | 0x4e00..=0x9fff
            | 0xf900..=0xfaff
            | 0x20000..=0x2fa1f
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn import_engine_options() -> msime_engine_bridge::EngineOptions {
        msime_engine_bridge::EngineOptions {
            resources: String::new(),
            user_data: String::new(),
            cache: String::new(),
            dictionaries: String::new(),
            scheme: 0,
            shuangpin_profile: 0,
            shuangpin_preedit_uses_raw: true,
            learning: false,
            autocorrect_transposition: true,
            autocorrect_neighbor: true,
            fuzzy_pinyin_rules: 0,
            helpcode: false,
            show_helpcode: true,
            helpcode_schema: "ziranma".into(),
            chinese_punctuation: true,
            paired_punctuation: true,
            punctuation_lock: 0,
            frequency_mode: "promote".into(),
            frequency_trigger_count: 1,
            frequency_linear_step: 1,
            mixed_english: true,
            english_minimum_prefix: 2,
            mixed_emoji: false,
            mixed_kaomoji: false,
            local_unicode: true,
            local_date_time: true,
            local_quick_phrase: true,
            local_emoji: true,
            local_kaomoji: true,
            local_super_jianpin: true,
            local_temporary_english: true,
            local_temporary_japanese: true,
        }
    }

    #[test]
    fn malformed_and_oversized_requests_are_redacted() {
        for bytes in [b"invalid-fixture".as_slice(), b"{}", b"{\"options\":null}"] {
            assert_eq!(
                dictionary_request_json(bytes).unwrap_err(),
                "invalid dictionary request"
            );
        }
        assert_eq!(
            dictionary_request_json(&vec![0u8; 65537]).unwrap_err(),
            "invalid dictionary buffer"
        );
    }

    #[test]
    fn import_maps_shared_entries_onto_the_requested_engine_kind() {
        // Row semantics are covered exhaustively in
        // client-core::dictionary_import, which is unit-testable without the
        // Engine. This asserts only the mapping this module is responsible for.
        let (standard, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "你好\tni'hao\t7\n# comment\n西安\txi'an\n",
            None,
        )
        .unwrap();
        assert_eq!(standard.len(), 2);
        assert_eq!(standard[0].value, "你好");
        assert_eq!(standard[0].key, "ni'hao");
        assert_eq!(standard[0].weight, 7);
        assert_eq!(standard[1].weight, 10000);
        assert!(standard.iter().all(|entry| entry.kind == Kind::Pinyin.into()));
        assert_eq!(report.failed, 0);
        assert!(!report.truncated);

        let (windows, _) = parse_import(&Kind::Wubi, "windows", "wq\t你好\t9\n", None).unwrap();
        assert_eq!(windows[0].key, "wq");
        assert_eq!(windows[0].value, "你好");
        assert_eq!(windows[0].kind, Kind::Wubi.into());
    }

    #[test]
    fn engine_backed_pinyin_import_resolves_lengths_and_reports_invalid_rows() {
        let options = import_engine_options();
        let (entries, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "西安\txian\n坏词\tzzzz\n你好\tnihao\n",
            Some(&options),
        )
        .unwrap();

        assert_eq!(
            entries
                .iter()
                .map(|entry| entry.key.as_str())
                .collect::<Vec<_>>(),
            ["xi'an", "ni'hao"]
        );
        assert_eq!(report.failed, 1);
        assert_eq!(report.first_failures[0].line, 2);
        assert_eq!(
            report.first_failures[0].issue,
            msime_client_core::dictionary_import::ImportIssue::Pinyin
        );

        let (wubi, _) =
            parse_import(&Kind::Wubi, "windows", "wq\t你好\t9\n", Some(&options)).unwrap();
        assert_eq!(wubi[0].key, "wq");
    }

    #[test]
    fn personal_import_accepts_the_apple_envelope_and_rejects_duplicates() {
        let text = r#"{
          "format": "msime-personal-dictionary",
          "version": 1,
          "entries": [
            {"kind":"pinyin","key":"ni hao","value":"你好","weight":100000},
            {"kind":"quickPhrase","key":"hello1","value":"你好！","weight":2}
          ]
        }"#;
        let entries = parse_personal_dictionary_import(text).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[1].kind, PersonalWordKind::QuickPhrase);

        let duplicate = text.replace(
            r#"{"kind":"quickPhrase","key":"hello1","value":"你好！","weight":2}"#,
            r#"{"kind":"pinyin","key":"ni hao","value":"你好","weight":3}"#,
        );
        assert_eq!(
            parse_personal_dictionary_import(&duplicate).unwrap_err(),
            "duplicate personal dictionary entry"
        );
    }

    #[test]
    fn personal_import_enforces_file_and_entry_bounds() {
        let empty = r#"{"format":"msime-personal-dictionary","version":1,"entries":[]}"#;
        assert_eq!(
            parse_personal_dictionary_import(empty).unwrap_err(),
            "invalid personal dictionary entry count"
        );
        let malformed = r#"{"format":"msime-personal-dictionary","version":1,"entries":[{"kind":"pinyin","key":"NI","value":"坏","weight":1}]}"#;
        assert_eq!(
            parse_personal_dictionary_import(malformed).unwrap_err(),
            "invalid personal dictionary entry"
        );
        assert_eq!(
            parse_personal_dictionary_import(&"x".repeat(1_048_577)).unwrap_err(),
            "personal dictionary file is too large"
        );
    }

    #[test]
    fn a_single_unusable_row_is_reported_rather_than_failing_the_import() {
        let (entries, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "你好\tni'hao\n没有制表符\n世界\tshi'jie\n",
            None,
        )
        .unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(report.failed, 1);
        assert_eq!(report.first_failures[0].line, 2);
    }

    #[test]
    fn an_unusable_envelope_is_still_rejected_outright() {
        assert!(parse_import(&Kind::Pinyin, "hans", "你好\tni'hao", None).is_err());
        assert!(parse_import(&Kind::Pinyin, "standard", "# only comments\n", None).is_err());
        // Every row unusable means nothing to import.
        assert!(parse_import(&Kind::Wubi, "windows", "abcde\t你好", None).is_err());
    }
}
